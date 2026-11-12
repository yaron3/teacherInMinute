//
//  StudentAskUITests.swift
//  TeacherMinuteUITests
//
//  A signed-in student asking a question, all the way to Send, against the
//  local Firebase emulators. QA test plan:
//
//   IOS-D-01  text of 10+ characters → Find a teacher: the search screen, a
//             searching question with that text, an invite card for the
//             online teacher; cancelling cancels it
//   IOS-D-02  a photo from the library and no text → a question carrying the
//             photo, on the teacher's card too
//   IOS-D-03  under 10 characters is refused on the phone, with nothing sent;
//             over the 1024-character limit is refused by the backend with a
//             message saying the limit
//   IOS-D-04  under 2 minutes → the "not enough minutes" offer, nothing sent
//   IOS-D-05  over the allowance of lessons a minute → "asking too quickly",
//             nothing sent
//
//  Sending is safe here, and only here: a debug build launched with
//  `-firebaseEmulatorHost` talks to nothing but the emulators, and the only
//  teacher online is one this suite writes into the emulator's database.
//  Start the emulators as for ProTeacherAcceptRaceUITests.
//
//  The home has no topic choice — every question goes out as "any" — so the
//  plan's "no topic" case cannot be reached from the app.
//
//  The rate limit counts lessons a teacher accepted, not questions asked
//  (backend rateLimit.ts), so IOS-D-05 seeds two recent lessons rather than
//  asking three times.
//

import XCTest

final class StudentAskUITests: XCTestCase {

    private let backend = EmulatorBackend()
    private var app: XCUIApplication!
    private var teacherUid: String?

    private let systemPromptHosts = [
        "com.apple.springboard",
        "com.apple.AuthenticationServicesUI",
        "com.apple.Passwords",
        "com.apple.CredentialSharingService",
    ].map { XCUIApplication(bundleIdentifier: $0) }

    // Each in English, then Hebrew (backend/Firebase/remote_config_tim.json).
    private let tooShortMessages = ["Take a photo of it, or write at least 10 characters.", "צלם אותה, או כתוב לפחות 10 תווים."]
    private let tooLongMessages = ["Please shorten it to 1024 characters.", "קצרו אותה ל-1024 תווים."]
    private let tooQuicklyMessages = ["You're asking too quickly.", "שליחת השאלות מהירה מדי."]
    private let couldNotSendTitles = ["Could Not Send Question", "לא ניתן לשלוח את השאלה"]

    private var findTeacher: XCUIElement { app.buttons["find_teacher"] }
    private var questionField: XCUIElement { app.textViews["question_text"] }
    private var searchCancel: XCUIElement { app.buttons["search_details_cancel"] }

    override func setUp() async throws {
        continueAfterFailure = false
        guard await backend.isRunning() else {
            throw XCTSkip("Firebase emulators not running; see ProTeacherAcceptRaceUITests for how to start them")
        }
        await MainActor.run {
            // Asking for an audio lesson asks for the microphone.
            addUIInterruptionMonitor(withDescription: "iOS system prompt") { alert in
                for label in ["Allow", "OK", "Allow Paste"] where alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return true
                }
                return false
            }
        }
    }

    // Synchronous on purpose: an async tearDown that quits the app through
    // `await MainActor.run` hangs the whole run after a failed assertion.
    override func tearDownWithError() throws {
        MainActor.assumeIsolated { app?.terminate() }
        // Nobody stays online on the emulators after the suite. Waited for on a
        // background queue, since XCTest's own waits hold the main thread.
        guard let teacherUid else { return }
        let done = DispatchSemaphore(value: 0)
        let backend = backend
        Task.detached {
            try? await backend.patch("teachers/\(teacherUid)", ["status": "offline"])
            try? await backend.delete("onlineTeachers/\(teacherUid)")
            done.signal()
        }
        _ = done.wait(timeout: .now() + 15)
    }

    // MARK: - Tests

    /// IOS-D-01: a text question goes out, and cancelling takes it back.
    @MainActor
    func testAskingWithTextStartsASearch() async throws {
        let student = try await signedInStudent(minutes: 60)
        try await bringATeacherOnline()
        let text = "What is the derivative of x squared? \(Int.random(in: 1000...9999))"

        try ask(text)
        try require(searchCancel.waitForExistence(timeout: 30), "Find a teacher did not start a search")

        let qid = try await waitForQuestion(of: student.uid)
        let question = try await backend.fields("questions/\(qid)") ?? [:]
        XCTAssertEqual(stringValue(question["text"]), text)
        try require(["searching", "accepted"].contains(stringValue(question["status"]) ?? ""),
                      "the question is \(stringValue(question["status"]) ?? "missing")")
        // Earlier suites may have left other emulator teachers online, so the
        // first wave need not include this suite's teacher: whoever it went to
        // must hold a card.
        let invited = try await invitedTeachers(qid)
        let first = try XCTUnwrap(invited.first, "the question was sent to no teacher")
        let card = try await backend.exists("teacherInvites/\(first)/\(qid)")
        try require(card, "an invited teacher has no card")

        try require(tapWhenHittable(searchCancel, "the search's close button"), "the search could not be closed")
        var status = ""
        for _ in 0..<20 where status != "cancelled" {
            status = stringValue(try await backend.fields("questions/\(qid)")?["status"]) ?? ""
            if status != "cancelled" { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        XCTAssertEqual(status, "cancelled", "closing the search did not cancel the question")
        try require(waitForHome(timeout: 20), "closing the search did not return home")
    }

    /// IOS-D-02: a photo from the library and no words. A simulator has no
    /// camera, so Attach photo opens the library; the camera itself stays a
    /// manual check. Needs a photo in the simulator's library
    /// (`xcrun simctl addmedia <udid> photo.jpg`).
    @MainActor
    func testAskingWithOnlyAPhotoSendsThePhoto() async throws {
        let student = try await signedInStudent(minutes: 60)
        try await bringATeacherOnline()

        try require(tapWhenHittable(app.buttons["capture_question_photo"], "Attach photo"), "no Attach photo at home")
        let picked = pickFirstLibraryPhoto()
        try require(picked, "no photo could be picked from the library")
        try require(app.buttons["delete_question_photo"].waitForExistence(timeout: 30), "the photo was not attached")
        // Find a teacher is disabled while the photo uploads.
        let uploaded = waitForAny([findTeacher], timeout: 30) { } != nil
        try require(uploaded && waitForEnabled(findTeacher, timeout: 60), "the photo never finished uploading")
        try require(tapWhenHittable(findTeacher, "Find a teacher"), "Find a teacher was never tappable")
        try require(searchCancel.waitForExistence(timeout: 30), "a photo question did not start a search")

        let qid = try await waitForQuestion(of: student.uid)
        let question = try await backend.fields("questions/\(qid)") ?? [:]
        let photos = (((question["photoUrls"] as? [String: Any])?["arrayValue"] as? [String: Any])?["values"]
            as? [[String: Any]])?.compactMap { $0["stringValue"] as? String } ?? []
        XCTAssertEqual(photos.count, 1, "the question carries \(photos.count) photos")
        try require(photos.first?.contains("questionImages%2F\(student.uid)%2F") ?? false,
                      "the photo is not in the student's folder: \(photos)")
        let sentTo = try await invitedTeachers(qid)
        let teacher = try XCTUnwrap(sentTo.first, "the question was sent to no teacher")
        var cardPhotos: [String] = []
        for _ in 0..<20 where cardPhotos.isEmpty {
            cardPhotos = (try await backend.value("teacherInvites/\(teacher)/\(qid)/photoUrls") as? [String]) ?? []
            if cardPhotos.isEmpty { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        XCTAssertEqual(cardPhotos, photos, "the teacher's card does not show the photo")

        try require(tapWhenHittable(searchCancel, "the search's close button"), "the search could not be closed")
    }

    /// Taps the first photo in the system photo picker. The picker is drawn by
    /// another process and shows none of its photos to XCUITest, so the tap
    /// goes by position: the first cell of its grid, below the "Private
    /// Access to Photos" banner. A single-selection picker closes on the tap.
    @MainActor
    private func pickFirstLibraryPhoto() -> Bool {
        pause(seconds: 3) // the picker sliding up
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.165, dy: 0.43)).tap()
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if app.buttons["delete_question_photo"].exists { return true }
            pause(seconds: 0.5)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.isEnabled { return true }
            pause(seconds: 0.5)
        } while Date() < deadline
        return false
    }

    /// IOS-D-03: fewer than 10 characters never leaves the phone.
    @MainActor
    func testAShortQuestionIsRefusedOnThePhone() async throws {
        let student = try await signedInStudent(minutes: 60)
        try await bringATeacherOnline()

        try ask("2+2=?")

        try require(nil != waitForText(tooShortMessages, timeout: 15), "a short question showed no message")
        XCTAssertFalse(searchCancel.exists, "a short question started a search")
        let asked = try await backend.count("questions", where: "studentUid", is: student.uid)
        XCTAssertEqual(asked, 0, "a short question was sent")
    }

    /// IOS-D-03: over the length limit, the backend refuses with the limit.
    @MainActor
    func testATooLongQuestionIsRefusedWithTheLimit() async throws {
        let student = try await signedInStudent(minutes: 60)
        try await bringATeacherOnline()

        try ask(String(repeating: "Long question. ", count: 70)) // 1050 characters

        try require(nil != waitForText(tooLongMessages, timeout: 30), "a long question showed no length message")
        try require(nil != waitForText(couldNotSendTitles, timeout: 1), "the refusal had no title")
        let asked = try await backend.count("questions", where: "studentUid", is: student.uid)
        XCTAssertEqual(asked, 0, "a question over the limit was sent")
    }

    /// IOS-D-04: one minute left is not enough to ask.
    @MainActor
    func testTooFewMinutesOffersMinutesInstead() async throws {
        let student = try await signedInStudent(minutes: 1)
        try await bringATeacherOnline()

        try ask("How do I factor x squared minus nine?")

        try require(app.buttons["not_enough_minutes_primary"].waitForExistence(timeout: 20),
                      "one minute left did not offer minutes")
        XCTAssertFalse(searchCancel.exists, "a student without minutes started a search")
        let asked = try await backend.count("questions", where: "studentUid", is: student.uid)
        XCTAssertEqual(asked, 0, "a student without minutes sent a question")
    }

    /// IOS-D-05: two lessons in the last minute use up the allowance.
    @MainActor
    func testAskingTooQuicklyIsRefusedWithAWait() async throws {
        let student = try await signedInStudent(minutes: 60)
        try await bringATeacherOnline()
        let now = Int(Date().timeIntervalSince1970 * 1000)
        try await backend.merge("rateLimits/\(student.uid)", ["sessionsAt": [now - 20_000, now - 10_000]])

        try ask("How do I factor x squared minus nine?")

        try require(nil != waitForText(tooQuicklyMessages, timeout: 30), "asking too quickly showed no wait")
        let asked = try await backend.count("questions", where: "studentUid", is: student.uid)
        XCTAssertEqual(asked, 0, "a rate-limited question was sent")
    }

    // MARK: - Steps

    /// A student account with `minutes`, signed in through the guest's menu.
    @MainActor
    private func signedInStudent(minutes: Int) async throws -> EmulatorBackend.Account {
        let student = try await backend.createAccount(prefix: "ask.student")
        try await backend.merge(
            "users/\(student.uid)",
            ["role": "student", "fullName": "Asking Student", "remainingMinutes": minutes, "totalMinutes": minutes]
        )
        app = XCUIApplication()
        app.launchArguments = [
            "-firebaseEmulatorHost", EmulatorBackend.host,
            "-firebaseEmulatorSignOut", "YES",
            "-tutorial.student.hidden", "YES",
        ]
        app.launch()

        let start = app.buttons["student_intro_start"]
        try require(tapWhenHittable(start, "the intro's Start", timeout: 60), "the intro's Start never appeared")
        // Right after launch the intro can swallow the first tap.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, start.exists {
            pause(seconds: 3)
            _ = tapIfPresent(start)
        }
        try require(waitForHome(timeout: 60), "Start did not reach home")

        try require(tapWhenHittable(app.buttons["side_menu_button"], "the menu button"), "no menu button")
        try require(tapWhenHittable(app.buttons["side_menu_log_in"], "the menu's Log in"), "no Log in in a guest's menu")
        let emailField = app.textFields["email_input"]
        try require(emailField.waitForExistence(timeout: 20), "the login form did not open")
        try type(student.email, into: emailField, "the login email field")
        try type(student.password, into: app.secureTextFields["password_input"], "the login password field")
        dismissKeyboard()
        let submit = app.buttons["login_submit"]
        try require(tapWhenHittable(submit, "Log in"), "Log in was never tappable")
        // The guest's home is still underneath until the login screen closes.
        let closed = Date().addingTimeInterval(60)
        while submit.exists && Date() < closed { pause(seconds: 0.5) }
        try require(!submit.exists, "the login screen never closed")
        try require(waitForHome(timeout: 90), "logging in did not reach home")
        return student
    }

    /// One teacher online on the emulators, so the app has someone to ask.
    private func bringATeacherOnline() async throws {
        let uid = "ask-teacher-\(Int(Date().timeIntervalSince1970 * 1000))"
        teacherUid = uid
        try await backend.merge("users/\(uid)", ["role": "teacher", "fullName": "Emulator Teacher"])
        try await backend.put("teachers/\(uid)", [
            "status": "offline", "subjects": ["algebra", "calculus"], "displayName": "Emulator Teacher",
        ])
        try await backend.patch("teachers/\(uid)", [
            "status": "online", "lastSeenAt": Int(Date().timeIntervalSince1970 * 1000),
        ])
        var listed = false
        for _ in 0..<30 where !listed {
            listed = try await backend.exists("onlineTeachers/\(uid)")
            if !listed { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        if !listed { throw StepFailed("the emulator teacher was never listed online") }
    }

    /// Opens the text tab, writes `text` and taps Find a teacher.
    @MainActor
    private func ask(_ text: String) throws {
        try require(tapWhenHittable(app.buttons["question_home_mode_text"], "the Text tab"), "no Text tab at home")
        try require(tapWhenHittable(questionField, "the question field"), "no question field")
        questionField.typeText(text)
        dismissKeyboard()
        try require(tapWhenHittable(findTeacher, "Find a teacher"), "Find a teacher was never tappable")
        // Tapping the app again lets the interruption monitor answer a
        // microphone prompt, if one came up.
        pause(seconds: 1)
        if !searchCancel.exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap() }
    }

    /// Who the question was sent to, once dispatch has sent it.
    private func invitedTeachers(_ qid: String) async throws -> [String] {
        for _ in 0..<20 {
            let field = try await backend.fields("questions/\(qid)")?["alreadyInvited"] as? [String: Any]
            let invited = ((field?["arrayValue"] as? [String: Any])?["values"] as? [[String: Any]])?
                .compactMap { $0["stringValue"] as? String } ?? []
            if !invited.isEmpty { return invited }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        return []
    }

    private func waitForQuestion(of studentUid: String) async throws -> String {
        for _ in 0..<40 {
            let ids = try await backend.documentIDs("questions", where: "studentUid", is: studentUid)
            if let qid = ids.first { return qid }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw StepFailed("no question was created")
    }

    @MainActor
    private func waitForHome(timeout: TimeInterval) -> Bool {
        let textTab = app.buttons["question_home_mode_text"]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            // Whatever a signed-in student may be shown first.
            _ = tapIfPresent(app.buttons["permissions_setup_skip"])
            _ = tapIfPresent(app.buttons["student_tutorial_skip"])
            _ = tapIfPresent(app.buttons["verify_email_not_now"])
            closeSavePasswordSheet()
            if textTab.exists && textTab.isHittable && !app.textFields["email_input"].exists { return true }
            pause(seconds: 0.5)
        } while Date() < deadline
        return false
    }

    /// The first of `texts` to appear anywhere on screen.
    @MainActor
    private func waitForText(_ texts: [String], timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let screen = app.debugDescription
            if let found = texts.first(where: { screen.contains($0) }) { return found }
            pause(seconds: 0.5)
        } while Date() < deadline
        attach("screen", app.debugDescription)
        return nil
    }

    // MARK: - Typing and tapping

    @MainActor
    private func type(_ text: String, into field: XCUIElement, _ described: String) throws {
        try require(field.waitForExistence(timeout: 20), "no \(described)")
        try require(tapWhenHittable(field, described), "\(described) was never tappable")
        _ = closeStrongPasswordSheet(wait: 0.5)
        field.typeText(text)
    }

    @MainActor
    private func closeStrongPasswordSheet(wait: TimeInterval) -> Bool {
        let hosts = (systemPromptHosts + [app!]).filter { $0.state != .notRunning }
        let deadline = Date().addingTimeInterval(wait)
        repeat {
            for host in hosts {
                for label in ["xmark", "Close", "Not Now"] {
                    let button = host.buttons[label]
                    if button.exists && button.isHittable {
                        button.tap()
                        pause(seconds: 0.5)
                        return true
                    }
                }
            }
            pause(seconds: 0.25)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        let deadline = Date().addingTimeInterval(3)
        while app.keyboards.firstMatch.exists && Date() < deadline { pause(seconds: 0.3) }
    }

    @MainActor
    private func tapWhenHittable(_ element: XCUIElement, _ described: String, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            closeSavePasswordSheet()
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
            pause(seconds: 0.5)
        } while Date() < deadline
        return false
    }

    /// iOS offers to save the password just used to log in, a moment after
    /// home appears, and the sheet covers it.
    @MainActor
    private func closeSavePasswordSheet() {
        let sheet = app.sheets["Save Password?"]
        guard sheet.exists else { return }
        let notNow = sheet.buttons["Not Now"]
        if notNow.exists { notNow.tap() } else { _ = tapIfPresent(app.buttons["Not Now"]) }
        pause(seconds: 0.5)
    }

    @MainActor
    private func tapIfPresent(_ element: XCUIElement) -> Bool {
        guard element.exists && element.isHittable else { return false }
        element.tap()
        return true
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval, whileWaiting: () -> Void = {}) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let found = elements.first(where: \.exists) { return found }
            whileWaiting()
            pause(seconds: 0.5)
        } while Date() < deadline
        return nil
    }

    private func pause(seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [expectation(description: "poll")], timeout: seconds)
    }

    private func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Fails the test with `message` and a picture of the screen, ending it.
    @MainActor
    private func require(_ condition: Bool, _ message: String) throws {
        guard !condition else { return }
        attach("screen", app?.debugDescription ?? "no app")
        if let app {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "screenshot"
            shot.lifetime = .keepAlways
            add(shot)
        }
        throw StepFailed(message)
    }

    private struct StepFailed: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private func stringValue(_ field: Any?) -> String? { (field as? [String: Any])?["stringValue"] as? String }
}
