//
//  ProTeacherEmulatorTestCase.swift
//  TeacherMinuteUITests
//
//  What every Pro Teacher UI test on the local Firebase emulators shares: two
//  new teachers and a student on the emulators, Pro Teacher signed in as the
//  first teacher on its dashboard, a way to seed a question, and the waits and
//  taps that keep XCUITest steady. The suites themselves are
//  ProTeacherAcceptRaceUITests and ProTeacherDispatchUITests; see the header of
//  the first for how to start the emulators and install Pro Teacher.
//
//  Nothing here reaches production: the app is launched with
//  `-firebaseEmulatorHost`, which points a debug build at the emulators, and
//  every account and document is created on them.
//

import XCTest

class ProTeacherEmulatorTestCase: XCTestCase {

    let backend = EmulatorBackend()
    var app: XCUIApplication!

    /// The teacher signed in to the app, and the one this test plays.
    var appTeacher: EmulatorBackend.Account!
    var otherTeacher: EmulatorBackend.Account!
    var student: EmulatorBackend.Account!
    /// The question this test seeded.
    var currentQid = ""

    let topic = "algebra"
    let questionText = "Emulator race: solve 2x + 3 = 11"

    /// The dialog's message in either language; the app may run with Remote
    /// Config's Hebrew copy cached or on its English defaults.
    let takenMessages = ["Another teacher already answered it", "מורה אחר/ת כבר ענה/תה עליה"]
    /// The "student cancelled" dialog's title, in either language.
    let cancelledMessages = ["The student cancelled the session", "התלמיד/ה ביטל/ה את השיעור"]

    let systemPromptHosts = [
        "com.apple.springboard",
        "com.apple.AuthenticationServicesUI",
        "com.apple.Passwords",
        "com.apple.CredentialSharingService",
    ].map { XCUIApplication(bundleIdentifier: $0) }
    let promptDismissLabels = ["Not Now", "Don't Allow"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        // A question left searching would be backfilled to the next test's
        // teacher the moment it comes online, putting a second card on its
        // dashboard. Waited for on a background queue, since XCTest's own
        // waits hold the main thread.
        guard !currentQid.isEmpty else { return }
        let done = DispatchSemaphore(value: 0)
        let backend = backend
        let qid = currentQid
        Task.detached {
            try? await backend.merge("questions/\(qid)", ["status": "unanswered"])
            done.signal()
        }
        _ = done.wait(timeout: .now() + 15)
    }

    // MARK: - Scene

    /// Two new teachers and a student on the emulators, and the app signed in
    /// as the first teacher on its dashboard.
    @MainActor
    func signInAsNewTeacher() async throws {
        try await createAccounts()
        launchApp()
        openLoginForm()
        submitLogin(email: appTeacher.email, password: appTeacher.password)
        XCTAssertTrue(waitForDashboard(timeout: 90), "signing in did not reach the teacher dashboard")
    }

    /// The app's teacher, the other teacher and a student, in the emulators.
    @MainActor
    func createAccounts() async throws {
        guard await backend.isRunning() else {
            throw XCTSkip("Firebase emulators not running; see the header for how to start them")
        }
        appTeacher = try await backend.createAccount(prefix: "race.app-teacher")
        otherTeacher = try await backend.createAccount(prefix: "race.other-teacher")
        student = try await backend.createAccount(prefix: "race.student")
        for (account, name) in [(appTeacher!, "Race App Teacher"), (otherTeacher!, "Race Other Teacher")] {
            try await backend.merge("users/\(account.uid)", [
                "role": "teacher",
                "fullName": name,
                "phoneNumber": "+972500000000",
                "subjectSelections": ["math": [topic]],
            ])
        }
        // Enough minutes for createQuestion, which refuses a student with
        // fewer than two.
        try await backend.merge(
            "users/\(student.uid)",
            ["role": "student", "fullName": "Race Student", "remainingMinutes": 30]
        )
        attach("accounts", "app teacher \(appTeacher.email)\nother teacher \(otherTeacher.email)")

        addUIInterruptionMonitor(withDescription: "iOS system prompt") { [promptDismissLabels] alert in
            for label in promptDismissLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    /// Launches Pro Teacher against the emulators. `signedOut` starts it at
    /// the welcome screen whatever an earlier run left signed in; without it
    /// the app restores the session it had.
    @MainActor
    func launchApp(signedOut: Bool = true) {
        app = XCUIApplication(bundleIdentifier: "com.yaronj.tim")
        app.launchArguments = ["-firebaseEmulatorHost", EmulatorBackend.host]
        if signedOut { app.launchArguments += ["-firebaseEmulatorSignOut", "YES"] }
        app.launch()
    }

    /// From the welcome screen to the login form.
    @MainActor
    func openLoginForm() {
        // A tap while the welcome screen is still animating in does nothing,
        // so it is repeated until the form opens.
        let emailField = app.textFields["email_input"]
        for _ in 0..<5 where !emailField.exists {
            XCTAssertTrue(tapWhenHittable(app.buttons["welcome_log_in"], "the welcome screen's Log in"),
                          "the welcome screen's Log in never appeared")
            _ = emailField.waitForExistence(timeout: 5)
        }
    }

    @MainActor
    func submitLogin(email: String, password: String) {
        let emailField = app.textFields["email_input"]
        let passwordField = app.secureTextFields["password_input"]
        clear(emailField)
        type(email, into: emailField, "the login email field")
        clear(passwordField)
        type(password, into: passwordField, "the login password field")
        dismissKeyboard()
        XCTAssertTrue(tapWhenHittable(app.buttons["login_submit"], "Log in"), "Log in was never tappable")
    }

    /// Empties a text field that may hold an earlier attempt.
    @MainActor
    func clear(_ field: XCUIElement) {
        guard field.waitForExistence(timeout: 10),
              let value = field.value as? String, !value.isEmpty,
              value != field.placeholderValue else { return }
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 2))
    }

    /// Waits for the teacher dashboard, getting past the first-run prompts.
    @MainActor
    func waitForDashboard(timeout: TimeInterval) -> Bool {
        let reached = waitForAny([app.switches["availability_toggle"], app.buttons["availability_toggle"]],
                                 timeout: timeout) { [self] in
            _ = tapIfPresent(app.buttons["permissions_setup_skip"])
            _ = tapIfPresent(app.buttons["Not Now"])
        }
        return reached != nil
    }

    /// A searching question already sent to both teachers, with both cards
    /// delivered — what dispatch leaves behind.
    func seedQuestion() async throws -> String {
        let qid = "race-\(UUID().uuidString.prefix(8).lowercased())"
        currentQid = qid
        let now = Date()
        for teacher in [appTeacher!, otherTeacher!] {
            try await backend.merge("questions/\(qid)/invites/\(teacher.uid)", [
                "teacherUid": teacher.uid,
                "response": "pending",
                "wave": 1,
                "invitedAt": now,
                "expiresAt": now.addingTimeInterval(180),
            ])
        }
        try await backend.merge("questions/\(qid)", [
            "studentUid": student.uid,
            "status": "searching",
            "topic": topic,
            "text": questionText,
            "conversationType": "text",
            "dispatchWave": 1,
            "alreadyInvited": [appTeacher.uid, otherTeacher.uid],
            // The Cloud Tasks emulator runs a delayed task at once, so the
            // abandoned-lesson check that production runs minutes after an
            // accept would write the lesson off within a second — and a late
            // tap would then be told the student cancelled. A student who has
            // already joined a started lesson keeps the check away.
            "joinedParticipants": [student.uid],
            "lessonId": "\(qid)-lesson",
            "createdAt": now,
            "updatedAt": now,
        ])
        for teacher in [appTeacher!, otherTeacher!] {
            try await backend.put("teacherInvites/\(teacher.uid)/\(qid)", card(for: qid))
        }
        return qid
    }

    // MARK: - Real dispatch

    /// Leaves exactly the two test teachers online, so a question asked
    /// through the real createQuestion reaches them and nobody else. Teachers
    /// from earlier runs are taken offline; the app's teacher went online by
    /// itself at launch, and the other teacher is put online here.
    @MainActor
    func prepareRealDispatch() async throws {
        for uid in try await backend.childKeys("teachers") where uid != appTeacher.uid && uid != otherTeacher.uid {
            try await backend.patch("teachers/\(uid)", ["status": "offline"])
        }
        try await backend.put("teachers/\(otherTeacher.uid)", ["status": "online", "subjects": [topic]])

        var online = false
        for _ in 0..<30 {
            online = (try await backend.value("teachers/\(appTeacher.uid)/status") as? String) == "online"
            if online { break }
            pause()
        }
        XCTAssertTrue(online, "the app's teacher never went online")
    }

    /// The student asks, through the real createQuestion and dispatch.
    @MainActor
    func ask() async throws -> String {
        let outcome = try await backend.call(
            "createQuestion",
            as: student,
            data: ["topic": topic, "text": questionText, "conversationType": "text"]
        )
        let qid = try XCTUnwrap(outcome.result?["questionId"] as? String, "createQuestion: \(outcome)")
        currentQid = qid
        attach("question", qid)
        return qid
    }

    /// Waits until the database holds `teacher`'s invite card for `qid`.
    @MainActor
    func waitForInvite(of teacher: EmulatorBackend.Account, to qid: String, timeout: TimeInterval = 20) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if try await backend.exists("teacherInvites/\(teacher.uid)/\(qid)") { return true }
            pause(seconds: 0.5)
        } while Date() < deadline
        return false
    }

    func card(for qid: String) -> [String: Any] {
        [
            "questionId": qid,
            "topic": topic,
            "text": questionText,
            "expiresAt": Int(Date().addingTimeInterval(180).timeIntervalSince1970 * 1000),
            "wave": 1,
            "studentId": student.uid,
            "studentName": "Race Student",
            "conversationType": "text",
            "pricePerMinuteCents": 50,
        ]
    }

    // MARK: - App

    /// The test's own question's Accept. The dashboard can list other
    /// questions too, and the incoming-question overlay repeats the newest
    /// card, so there may be two of these; any one of them existing means the
    /// card is still up.
    var acceptButton: XCUIElement {
        app.buttons.matching(identifier: "invite_accept_\(currentQid)").firstMatch
    }

    /// The copy of this question's Accept the teacher can actually tap.
    @MainActor
    func visibleAcceptButton(timeout: TimeInterval = 30) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let copies = app.buttons.matching(identifier: "invite_accept_\(currentQid)").allElementsBoundByIndex
            if let visible = copies.first(where: { $0.exists && $0.isHittable }) { return visible }
            if !dismissSystemPromptIfPresent() { pause(seconds: 0.5) }
        } while Date() < deadline
        return nil
    }
    var dialogButton: XCUIElement { app.buttons["dialog_confirm_button"] }

    /// The copy of this question's `kind` button ("accept" or "decline") the
    /// teacher can actually tap.
    @MainActor
    func visibleCardButton(_ kind: String, timeout: TimeInterval = 30) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let copies = app.buttons.matching(identifier: "invite_\(kind)_\(currentQid)").allElementsBoundByIndex
            if let visible = copies.first(where: { $0.exists && $0.isHittable }) { return visible }
            if !dismissSystemPromptIfPresent() { pause(seconds: 0.5) }
        } while Date() < deadline
        return nil
    }

    func dialogText() -> String {
        app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
    }

    @MainActor
    func type(_ text: String, into field: XCUIElement, _ described: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 20), "no \(described)")
        XCTAssertTrue(tapWhenHittable(field, described), "\(described) was never tappable")
        field.typeText(text)
    }

    @MainActor
    func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        _ = waitForDisappearance(app.keyboards.firstMatch, timeout: 3)
    }

    // MARK: - Waiting and tapping

    @MainActor
    func dismissSystemPromptIfPresent() -> Bool {
        for host in systemPromptHosts + [app].compactMap({ $0 }) {
            for label in promptDismissLabels {
                let button = host.buttons[label]
                if button.exists && button.isHittable {
                    button.tap()
                    return true
                }
            }
        }
        return false
    }

    /// Taps once nothing covers the element: `tap()` on a covered element
    /// fails the test outright.
    @MainActor
    func tapWhenHittable(_ element: XCUIElement, _ described: String, timeout: TimeInterval = 30) -> Bool {
        guard waitForHittable(element, timeout: timeout) else { return false }
        element.tap()
        return true
    }

    @MainActor
    func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.isHittable { return true }
            if !dismissSystemPromptIfPresent() { pause(seconds: 0.5) }
        } while Date() < deadline
        return false
    }

    @MainActor
    func tapIfPresent(_ element: XCUIElement) -> Bool {
        guard element.exists && element.isHittable else { return false }
        element.tap()
        return true
    }

    func waitForAny(
        _ elements: [XCUIElement],
        timeout: TimeInterval,
        whileWaiting: () -> Void = {}
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let found = elements.first(where: \.exists) { return found }
            whileWaiting()
            pause(seconds: 0.5)
        } while Date() < deadline
        return nil
    }

    func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline {
            pause(seconds: 0.5)
        }
        return !element.exists
    }

    func pause(seconds: TimeInterval = 1) {
        _ = XCTWaiter.wait(for: [expectation(description: "poll")], timeout: seconds)
    }

    func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
