//
//  StudentOnboardingUITests.swift
//  TeacherMinuteUITests
//
//  Instant Teacher's guest start and sign-up, against the real backend on the
//  local Firebase emulators. QA test plan:
//
//   IOS-S-01  Start makes one anonymous user: users/{uid} role student,
//             isAnonymous true, no minutes; home
//   IOS-S-02  a guest who asks is offered an account, and nothing is sent
//   IOS-S-03  a guest who signs up from that offer keeps the guest's uid,
//             now an email/password account, isAnonymous false
//   IOS-S-06  a guest's question, words and a photo, is back after signing up
//             from the offer, and goes out as written once there are minutes
//   IOS-S-09  a guest who logs in to an existing account is signed in to it,
//             and the guest account and its profile are deleted
//   IOS-S-11  a guest signing up with an address in use is refused, with no
//             second account, and stays the same guest
//   IOS-S-12  killed and relaunched, a guest is the same guest, still home
//   IOS-S-14  a guest who taps Buy minutes is offered an account instead
//   IOS-S-16  a teacher account is turned away with the other app's notice,
//             signed out, its presence untouched
//   IOS-S-17  a guest's menu offers Log in; their profile offers an account,
//             with no empty name to fill
//
//  The app under test is the scheme's own, Instant Teacher, launched with
//  `-firebaseEmulatorHost` so a debug build talks only to the emulators.
//  Start them as for ProTeacherAcceptRaceUITests. Nothing is dispatched: a
//  guest has no minutes, and no teacher here is online.
//
//  The tests tell the app's guest apart from other accounts by creation time:
//  run them on their own, not alongside another suite signing up on the same
//  emulators.
//

import XCTest

final class StudentOnboardingUITests: XCTestCase {

    private let backend = EmulatorBackend()
    private var app: XCUIApplication!

    private let systemPromptHosts = [
        "com.apple.springboard",
        "com.apple.AuthenticationServicesUI",
        "com.apple.Passwords",
        "com.apple.CredentialSharingService",
    ].map { XCUIApplication(bundleIdentifier: $0) }

    /// "This email address is already in use.", in either language.
    private let inUseMessages = ["This email address is already in use.", "כתובת המייל הזו כבר רשומה במערכת."]
    /// "Create an account or log in to buy minutes.", in either language.
    private let buyNeedsAccountMessages = ["Create an account or log in to buy minutes.", "צור חשבון או התחבר כדי לקנות דקות."]

    private var dialogButton: XCUIElement { app.buttons["dialog_confirm_button"] }
    private var findTeacher: XCUIElement { app.buttons["find_teacher"] }
    private var menuButton: XCUIElement { app.buttons["side_menu_button"] }

    override func setUp() async throws {
        continueAfterFailure = false
        guard await backend.isRunning() else {
            throw XCTSkip("Firebase emulators not running; see ProTeacherAcceptRaceUITests for how to start them")
        }
        await MainActor.run {
            addUIInterruptionMonitor(withDescription: "iOS system prompt") { alert in
                for label in ["Don't Allow", "Not Now"] where alert.buttons[label].exists {
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
    }

    // MARK: - Tests

    /// IOS-S-01: Start makes one anonymous student with no minutes.
    @MainActor
    func testStartingAsAGuestMakesOneAnonymousStudent() async throws {
        let guest = try await startAsGuest()
        let profile = try await backend.fields("users/\(guest.uid)") ?? [:]
        XCTAssertEqual(stringValue(profile["role"]), "student")
        XCTAssertEqual(boolValue(profile["isAnonymous"]), true)
        XCTAssertEqual(intValue(profile["remainingMinutes"]) ?? 0, 0, "a guest has minutes")
    }

    /// IOS-S-02: a guest who asks is offered an account; nothing is sent.
    @MainActor
    func testAGuestAskingIsOfferedAnAccount() async throws {
        let guest = try await startAsGuest()
        askAndExpectTheOffer()
        let asked = try await backend.count("questions", where: "studentUid", is: guest.uid)
        XCTAssertEqual(asked, 0, "a guest's question was created")
    }

    /// IOS-S-03: signing up from the offer keeps the guest's uid.
    @MainActor
    func testAGuestSigningUpKeepsTheirUid() async throws {
        let guest = try await startAsGuest()
        askAndExpectTheOffer()
        XCTAssertTrue(tapWhenHittable(app.buttons["not_enough_minutes_primary"], "Create account"),
                      "the offer's Create account was never tappable")
        let email = EmulatorBackend.newEmail(prefix: "guest.signup")
        let password = "Emulator-\(Int.random(in: 100_000...999_999))"
        XCTAssertTrue(app.textFields["sign_up_email"].waitForExistence(timeout: 20), "Create account did not open sign-up")
        fillSignUp(email: email, password: password)
        submitSignUp()
        finishOnboarding(name: "Guest Turned Student")

        let users = try await backend.users(withEmail: email)
        XCTAssertEqual(users.map(\.uid), [guest.uid], "the account is not the guest's uid")
        XCTAssertEqual(users.first?.providers, ["password"])
        let profile = try await backend.fields("users/\(guest.uid)") ?? [:]
        XCTAssertEqual(boolValue(profile["isAnonymous"]), false, "the profile still says anonymous")
        XCTAssertEqual(stringValue(profile["role"]), "student")
        let anonymousSince = try await anonymousUsers(since: guest.createdAt)
        XCTAssertTrue(anonymousSince.isEmpty, "signing up left another anonymous user")
    }

    /// IOS-S-06: a guest's question, words and a photo, waits through
    /// sign-up from the offer: after it, home has both back, and with the
    /// minutes the new account brings it goes out as it was written.
    @MainActor
    func testAGuestsQuestionSurvivesSigningUp() async throws {
        let guest = try await startAsGuest()
        let text = "Draft through sign-up: solve 3x + 4 = 19"

        // A simulator has no camera, so Attach photo opens the library.
        XCTAssertTrue(tapWhenHittable(app.buttons["capture_question_photo"], "Attach photo"), "no Attach photo at home")
        XCTAssertTrue(pickFirstLibraryPhoto(), "no photo could be picked from the library")
        XCTAssertTrue(waitForEnabled(findTeacher, timeout: 60), "the guest's photo never finished uploading")
        openTextTab()
        let field = app.textViews["question_text"]
        XCTAssertTrue(tapWhenHittable(field, "the question field"), "no question field at home")
        field.typeText(text)
        dismissKeyboard()

        let offer = app.buttons["not_enough_minutes_primary"]
        for _ in 0..<6 where !offer.exists {
            XCTAssertTrue(tapWhenHittable(findTeacher, "Find a teacher"), "Find a teacher was never tappable")
            if waitForAny([offer, dialogButton], timeout: 20) == dialogButton {
                dialogButton.tap()
                pause(seconds: 3)
            }
        }
        XCTAssertTrue(tapWhenHittable(offer, "Create account"), "a guest asking was not offered an account")
        let email = EmulatorBackend.newEmail(prefix: "guest.draft")
        let password = "Emulator-\(Int.random(in: 100_000...999_999))"
        XCTAssertTrue(app.textFields["sign_up_email"].waitForExistence(timeout: 20), "Create account did not open sign-up")
        // The minutes a new account brings (the sign-up reward, which the
        // emulators cannot serve from Remote Config), in place before the
        // home after sign-up reads the balance, as the reward is. Sign-up
        // keeps the guest's uid.
        try await backend.merge("users/\(guest.uid)", ["remainingMinutes": 30, "totalMinutes": 30])
        fillSignUp(email: email, password: password)
        submitSignUp()
        finishOnboarding(name: "Draft Keeping Student")

        // Back home, the question as it was: its words and its photo.
        let restored = app.textViews["question_text"]
        XCTAssertTrue(restored.waitForExistence(timeout: 20), "home did not come back on the question")
        XCTAssertEqual(restored.value as? String, text, "the question's words were not kept through sign-up")
        XCTAssertTrue(app.buttons["delete_question_photo"].waitForExistence(timeout: 20),
                      "the question's photo was not kept through sign-up")
        XCTAssertFalse(app.staticTexts["Your question is back, but its photo could not be kept. Please attach it again."].exists,
                       "the app says the photo was lost")

        // With a teacher online, it goes out as written.
        let teacher = try await bringATeacherOnline()
        let search = app.buttons["search_details_cancel"]
        for _ in 0..<6 where !search.exists {
            XCTAssertTrue(waitForEnabled(findTeacher, timeout: 60), "Find a teacher never became tappable")
            XCTAssertTrue(tapWhenHittable(findTeacher, "Find a teacher"), "Find a teacher was never tappable")
            if waitForAny([search, dialogButton, offer], timeout: 20) != search {
                // "Checking your balance" while the profile loads.
                XCTAssertFalse(offer.exists, "the new account's minutes did not reach home")
                _ = tapIfPresent(dialogButton)
                pause(seconds: 3)
            }
        }
        XCTAssertTrue(search.exists, "the kept question did not go out")

        var qid = ""
        for _ in 0..<40 where qid.isEmpty {
            qid = try await backend.documentIDs("questions", where: "studentUid", is: guest.uid).first ?? ""
            if qid.isEmpty { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        XCTAssertFalse(qid.isEmpty, "no question was created")
        let question = try await backend.fields("questions/\(qid)") ?? [:]
        XCTAssertEqual(stringValue(question["text"]), text, "the question went out with other words")
        let photos = (((question["photoUrls"] as? [String: Any])?["arrayValue"] as? [String: Any])?["values"]
            as? [[String: Any]])?.compactMap { $0["stringValue"] as? String } ?? []
        XCTAssertEqual(photos.count, 1, "the question went out with \(photos.count) photos")
        XCTAssertTrue(photos.first?.contains("questionImages%2F\(guest.uid)%2F") ?? false,
                      "the photo is not in the student's folder: \(photos)")
        _ = tapWhenHittable(search, "the search's close button")
        try await backend.patch("teachers/\(teacher)", ["status": "offline"])
    }

    /// IOS-S-09: logging in to an existing account deletes the guest.
    @MainActor
    func testAGuestLoggingInDropsTheGuestAccount() async throws {
        let existing = try await backend.createAccount(prefix: "guest.login")
        try await backend.merge("users/\(existing.uid)", ["role": "student", "fullName": "Existing Student"])
        let guest = try await startAsGuest()

        openSideMenu()
        XCTAssertTrue(tapWhenHittable(app.buttons["side_menu_log_in"], "the menu's Log in"), "no Log in in a guest's menu")
        let emailField = app.textFields["email_input"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 20), "the login form did not open")
        type(existing.email, into: emailField, "the login email field")
        type(existing.password, into: app.secureTextFields["password_input"], "the login password field")
        dismissKeyboard()
        XCTAssertTrue(tapWhenHittable(app.buttons["login_submit"], "Log in"), "Log in was never tappable")
        XCTAssertTrue(waitForHome(timeout: 90), "logging in did not reach home")

        var gone = false
        for _ in 0..<30 {
            let user = try await backend.user(uid: guest.uid)
            if user == nil { gone = true; break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTAssertTrue(gone, "the guest account is still in Auth")
        let guestProfile = try await backend.strings("users/\(guest.uid)")
        XCTAssertNil(guestProfile, "the guest's profile is still there")
        let existingUser = try await backend.user(uid: existing.uid)
        XCTAssertNotNil(existingUser, "the existing account is gone")
    }

    /// IOS-S-11: a guest signing up with a taken address is refused.
    @MainActor
    func testAGuestSigningUpWithATakenAddressIsRefused() async throws {
        let existing = try await backend.createAccount(prefix: "guest.taken")
        let guest = try await startAsGuest()
        askAndExpectTheOffer()
        XCTAssertTrue(tapWhenHittable(app.buttons["not_enough_minutes_primary"], "Create account"),
                      "the offer's Create account was never tappable")
        XCTAssertTrue(app.textFields["sign_up_email"].waitForExistence(timeout: 20), "Create account did not open sign-up")
        fillSignUp(email: existing.email, password: "Emulator-123456")
        submitSignUp()

        XCTAssertTrue(dialogButton.waitForExistence(timeout: 30), "a taken address showed no error")
        let screen = app.debugDescription
        XCTAssertTrue(inUseMessages.contains { screen.contains($0) }, "the error does not say the address is in use")
        dialogButton.tap()
        let users = try await backend.users(withEmail: existing.email)
        XCTAssertEqual(users.count, 1, "the address has \(users.count) accounts")
        let stillGuest = try await backend.user(uid: guest.uid)
        XCTAssertEqual(stillGuest?.isAnonymous, true, "the guest is no longer an anonymous account")
    }

    /// IOS-S-12: a guest killed and relaunched is the same guest, at home.
    @MainActor
    func testAGuestRelaunchedIsTheSameGuest() async throws {
        let guest = try await startAsGuest()
        app.terminate()
        launch(signedOut: false)
        XCTAssertTrue(waitForHome(timeout: 60), "the relaunched guest is not at home")
        XCTAssertFalse(app.buttons["student_intro_start"].exists, "the relaunch showed the intro again")
        let anonymous = try await anonymousUsers(since: guest.createdAt)
        XCTAssertEqual(anonymous.map(\.uid), [guest.uid], "the relaunch made another guest")
    }

    /// IOS-S-14: a guest who taps Buy minutes is offered an account.
    @MainActor
    func testAGuestBuyingMinutesIsOfferedAnAccount() async throws {
        _ = try await startAsGuest()
        openTextTab()
        let buy = app.buttons["load_minutes"]
        XCTAssertTrue(tapWhenHittable(buy, "Buy minutes"), "no Buy minutes on a guest's home")
        XCTAssertTrue(app.buttons["not_enough_minutes_primary"].waitForExistence(timeout: 15),
                      "Buy minutes did not offer an account")
        let screen = app.debugDescription
        XCTAssertTrue(buyNeedsAccountMessages.contains { screen.contains($0) },
                      "the offer does not say an account is needed to buy")
    }

    /// IOS-S-16: a teacher account is turned away, signed out, its presence
    /// untouched.
    @MainActor
    func testATeacherAccountIsTurnedAway() async throws {
        let teacher = try await backend.createAccount(prefix: "student-app.teacher")
        try await backend.merge("users/\(teacher.uid)", [
            "role": "teacher", "fullName": "Wrong App Teacher", "phoneNumber": "0521234567",
        ])
        try await backend.put("teachers/\(teacher.uid)", ["status": "offline"])
        _ = try await startAsGuest()

        openSideMenu()
        XCTAssertTrue(tapWhenHittable(app.buttons["side_menu_log_in"], "the menu's Log in"), "no Log in in a guest's menu")
        let emailField = app.textFields["email_input"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 20), "the login form did not open")
        type(teacher.email, into: emailField, "the login email field")
        type(teacher.password, into: app.secureTextFields["password_input"], "the login password field")
        dismissKeyboard()
        XCTAssertTrue(tapWhenHittable(app.buttons["login_submit"], "Log in"), "Log in was never tappable")

        XCTAssertTrue(dialogButton.waitForExistence(timeout: 60), "a teacher account got no notice")
        attach("notice", app.debugDescription)
        dialogButton.tap()
        let profile = try await backend.strings("users/\(teacher.uid)") ?? [:]
        XCTAssertEqual(profile["role"], "teacher", "signing in changed the teacher's role")
        let status = try await backend.value("teachers/\(teacher.uid)/status") as? String
        XCTAssertEqual(status, "offline", "the student app changed the teacher's presence")
        let online = try await backend.exists("onlineTeachers/\(teacher.uid)")
        XCTAssertFalse(online, "the teacher is listed online")

        // Signed out for real: a relaunch keeping the session is not signed
        // in as the teacher.
        app.terminate()
        launch(signedOut: false)
        let landed = waitForAny([app.buttons["student_intro_start"], menuButton], timeout: 60)
        XCTAssertNotNil(landed, "the app opened on neither the intro nor home")
        if landed == menuButton {
            openSideMenu()
            XCTAssertTrue(app.buttons["side_menu_log_in"].waitForExistence(timeout: 10),
                          "the teacher account stayed signed in")
        }
    }

    /// IOS-S-17: a guest's menu offers Log in; their profile says they have
    /// no account and offers one, with no empty name to fill.
    @MainActor
    func testAGuestsMenuAndProfileOfferAnAccount() async throws {
        _ = try await startAsGuest()
        openSideMenu()
        XCTAssertTrue(app.buttons["side_menu_log_in"].waitForExistence(timeout: 15), "a guest's menu has no Log in")
        XCTAssertTrue(tapWhenHittable(app.buttons["side_menu_item_profile"], "the menu's Profile"), "no Profile in a guest's menu")
        let create = app.buttons["profile_create_account_button"]
        XCTAssertTrue(create.waitForExistence(timeout: 20), "a guest's profile offers no account")
        scrollToHittable(create)
        XCTAssertEqual(app.textFields.count, 0, "a guest's profile has a field to fill")
        XCTAssertTrue(tapWhenHittable(create, "Create account"), "Create account was never tappable")
        XCTAssertTrue(app.textFields["sign_up_email"].waitForExistence(timeout: 20), "Create account did not open sign-up")
    }

    /// X-05 / X-06, the iPhone half: a guest signs up with the address and
    /// password the cross-platform run hands in, and is given 37 minutes. The
    /// Android half (StudentOnboardingTest.crossPlatformLogInFindsTheSameAccount)
    /// then logs in with them. Skipped unless the run sets CROSS_EMAIL and
    /// CROSS_PASSWORD (xcodebuild: TEST_RUNNER_CROSS_EMAIL, …).
    @MainActor
    func testCrossPlatformSignUpOnTheIPhone() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["CROSS_EMAIL"], let password = env["CROSS_PASSWORD"] else {
            throw XCTSkip("set TEST_RUNNER_CROSS_EMAIL and TEST_RUNNER_CROSS_PASSWORD to run the cross-platform sign-up")
        }
        let guest = try await startAsGuest()
        askAndExpectTheOffer()
        XCTAssertTrue(tapWhenHittable(app.buttons["not_enough_minutes_primary"], "Create account"), "no Create account in the offer")
        fillSignUp(email: email, password: password)
        submitSignUp()
        finishOnboarding(name: "Cross Platform Student")

        let users = try await backend.users(withEmail: email)
        XCTAssertEqual(users.map(\.uid), [guest.uid], "signing up on the iPhone did not keep the guest's uid")
        try await backend.merge("users/\(guest.uid)", ["remainingMinutes": 37])
        attach("cross-platform account", "\(email) uid=\(guest.uid)")
    }

    // MARK: - Steps

    /// Launches the app signed out and taps Start; returns the guest account
    /// that made, found as the one anonymous user created since.
    @MainActor
    private func startAsGuest() async throws -> EmulatorBackend.AuthUser {
        let before = Int(Date().timeIntervalSince1970 * 1000) - 2_000
        launch(signedOut: true)
        let start = app.buttons["student_intro_start"]
        XCTAssertTrue(tapWhenHittable(start, "the intro's Start", timeout: 60), "the intro's Start never appeared")
        // Right after launch the intro can swallow the first tap.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, start.exists {
            pause(seconds: 3)
            _ = tapIfPresent(start)
        }
        XCTAssertTrue(waitForHome(timeout: 60), "Start did not reach home")
        var guests: [EmulatorBackend.AuthUser] = []
        for _ in 0..<20 {
            guests = try await anonymousUsers(since: before)
            if !guests.isEmpty { break }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTAssertEqual(guests.count, 1, "Start made \(guests.count) anonymous users")
        let guest = try XCTUnwrap(guests.first)
        attach("guest", guest.uid)
        return guest
    }

    @MainActor
    private func launch(signedOut: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-firebaseEmulatorHost", EmulatorBackend.host, "-tutorial.student.hidden", "YES"]
        if signedOut { app.launchArguments += ["-firebaseEmulatorSignOut", "YES"] }
        app.launch()
    }

    private func anonymousUsers(since createdAt: Int) async throws -> [EmulatorBackend.AuthUser] {
        try await backend.allUsers().filter { $0.isAnonymous && $0.createdAt >= createdAt }
    }

    /// Writes a question and taps Find a teacher; a guest must get the offer
    /// of an account.
    @MainActor
    private func askAndExpectTheOffer() {
        openTextTab()
        let field = app.textViews["question_text"]
        XCTAssertTrue(tapWhenHittable(field, "the question field"), "no question field at home")
        field.typeText("Guest question: what is 2 + 2?")
        dismissKeyboard()
        let offer = app.buttons["not_enough_minutes_primary"]
        for _ in 0..<6 where !offer.exists {
            XCTAssertTrue(tapWhenHittable(findTeacher, "Find a teacher"), "Find a teacher was never tappable")
            // "Checking your balance" first, while the profile loads.
            if waitForAny([offer, dialogButton], timeout: 20) == dialogButton {
                dialogButton.tap()
                pause(seconds: 3)
            }
        }
        XCTAssertTrue(offer.exists, "a guest asking was not offered an account")
        XCTAssertFalse(app.buttons["search_details_cancel"].exists, "a guest's question went out")
    }

    /// Taps the first photo in the system photo picker, which shows none of
    /// its photos to XCUITest: by position, the first cell of its grid. A
    /// single-selection picker closes on the tap. Needs a photo in the
    /// simulator's library.
    @MainActor
    private func pickFirstLibraryPhoto() -> Bool {
        pause(seconds: 3) // the picker sliding up
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.165, dy: 0.43)).tap()
        return app.buttons["delete_question_photo"].waitForExistence(timeout: 15)
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

    /// One teacher online on the emulators, so the app has someone to ask;
    /// returns its uid.
    private func bringATeacherOnline() async throws -> String {
        let uid = "draft-teacher-\(Int(Date().timeIntervalSince1970 * 1000))"
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
        XCTAssertTrue(listed, "the emulator teacher was never listed online")
        return uid
    }

    @MainActor
    private func fillSignUp(email: String, password: String) {
        type(email, into: app.textFields["sign_up_email"], "the sign-up email field")
        typeSecure(password, into: app.secureTextFields["sign_up_password"], "the password field")
        typeSecure(password, into: app.secureTextFields["sign_up_confirm_password"], "the confirmation field")
        dismissKeyboard()
        let terms = app.buttons["sign_up_terms"]
        scrollToHittable(terms)
        XCTAssertTrue(tapWhenHittable(terms, "the terms box"), "the terms box was never tappable")
    }

    @MainActor
    private func submitSignUp() {
        let button = app.buttons["sign_up_continue"]
        scrollToHittable(button)
        XCTAssertTrue(tapWhenHittable(button, "the sign-up Continue"), "the sign-up Continue was never tappable")
    }

    /// Walks whichever steps follow sign-up — profile, email verification,
    /// permissions — to home.
    @MainActor
    private func finishOnboarding(name: String) {
        var filledName = false
        let deadline = Date().addingTimeInterval(150)
        while Date() < deadline {
            if waitForHome(timeout: 1) { return }
            let nameField = app.textFields["complete_profile_full_name"]
            if nameField.exists && !filledName {
                type(name, into: nameField, "the profile's name field")
                dismissKeyboard()
                filledName = true
            }
            let profileContinue = app.buttons["complete_profile_continue"]
            if filledName && profileContinue.exists && profileContinue.isEnabled {
                scrollToHittable(profileContinue)
                _ = tapIfPresent(profileContinue)
            }
            _ = tapIfPresent(app.buttons["verify_email_not_now"])
            _ = tapIfPresent(app.buttons["permissions_setup_skip"])
            _ = tapIfPresent(app.buttons["Not Now"])
        }
        attach("screen", app.debugDescription)
        XCTFail("sign-up did not reach home")
    }

    @MainActor
    private func waitForHome(timeout: TimeInterval) -> Bool {
        waitForAny([app.buttons["question_home_mode_text"]], timeout: timeout) { [self] in
            _ = tapIfPresent(app.buttons["permissions_setup_skip"])
        } != nil && !app.textFields["email_input"].exists
    }

    /// Home opens on the photo tab; the question field, Find a teacher and Buy
    /// minutes are on the text tab.
    @MainActor
    private func openTextTab() {
        XCTAssertTrue(tapWhenHittable(app.buttons["question_home_mode_text"], "the Text tab"), "no Text tab at home")
    }

    @MainActor
    private func openSideMenu() {
        XCTAssertTrue(tapWhenHittable(menuButton, "the menu button"), "the menu button was never tappable")
    }

    // MARK: - Typing and tapping

    @MainActor
    private func type(_ text: String, into field: XCUIElement, _ described: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 20), "no \(described)")
        XCTAssertTrue(tapWhenHittable(field, described), "\(described) was never tappable")
        field.typeText(text)
    }

    /// Types into a password field, closing iOS's "Use Strong Password?"
    /// sheet, which otherwise swallows the typing.
    @MainActor
    private func typeSecure(_ text: String, into field: XCUIElement, _ described: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 20), "no \(described)")
        for _ in 0..<3 {
            XCTAssertTrue(tapWhenHittable(field, described), "\(described) was never tappable")
            if !closeStrongPasswordSheet() { break }
        }
        field.typeText(text)
        _ = closeStrongPasswordSheet(wait: 0.5)
    }

    @MainActor
    private func closeStrongPasswordSheet(wait: TimeInterval = 2) -> Bool {
        // Asking a process that is not running retries for seconds per button.
        let hosts = (systemPromptHosts + [app!]).filter { $0.state != .notRunning }
        let deadline = Date().addingTimeInterval(wait)
        repeat {
            for host in hosts {
                for label in ["xmark", "Close", "Choose My Own Password", "Not Now"] {
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
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
            pause(seconds: 0.5)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func tapIfPresent(_ element: XCUIElement) -> Bool {
        guard element.exists && element.isHittable else { return false }
        element.tap()
        return true
    }

    @MainActor
    private func scrollToHittable(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
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

    // MARK: - Firestore REST values

    private func stringValue(_ field: Any?) -> String? { (field as? [String: Any])?["stringValue"] as? String }
    private func boolValue(_ field: Any?) -> Bool? { (field as? [String: Any])?["booleanValue"] as? Bool }
    private func intValue(_ field: Any?) -> Int? {
        let value = (field as? [String: Any])?["integerValue"]
        return (value as? String).flatMap(Int.init) ?? (value as? Int)
    }
}
