//
//  AccountLifecycleUITests.swift
//  TeacherMinuteUITests
//
//  The whole life of a student account, end to end, against the live backend:
//
//   1. sign up a brand-new email account (from the anonymous start, through
//      the menu's Log in → Sign up), and walk onboarding to the home screen;
//   2. send a real question, then cancel the search;
//   3. log out;
//   4. log back in with the new account;
//   5. visit every section of the side menu;
//   6. delete the account;
//   7. try to log in with it again, which must be refused.
//
//  ── The question is real ──
//  Dispatch offers it to online teachers — real people. Its text opens with
//  "QA Testing" so a teacher who sees it knows not to accept, and the test
//  cancels the search a few seconds after it starts. Run this only when that
//  is acceptable; see the project's CLAUDE.md on demo questions.
//
//  ── Cost of a run ──
//  Every run creates one account with a fresh address, and if the sign-up
//  reward is on in Remote Config that address takes one of its
//  `signup_reward_student_slots`. The account is deleted at the end; if the
//  test fails before step 6, delete it from the admin page (the address is
//  printed in the test log and attached to the result).
//
//  ── Running it ──
//  It types a password into the live Firebase backend, so it is run by hand:
//
//    xcodebuild test -workspace teacher-minute/Project.xcworkspace \
//      -scheme "Instant Teacher" -destination 'platform=iOS Simulator,id=<udid>' \
//      -parallel-testing-enabled NO -skipMacroValidation SKIP_ACTION=none \
//      -only-testing:TeacherMinuteUITests/AccountLifecycleUITests
//
//  `TIM_QA_EMAIL_DOMAIN` overrides the domain of the generated address.
//
//  Controls are found by accessibility identifier wherever the app gives
//  one, so the app's language does not matter.
//

import XCTest

final class AccountLifecycleUITests: XCTestCase {

    private var app: XCUIApplication!

    /// A new address every run, so sign-up never meets an existing account.
    private lazy var email: String = {
        let domain = ProcessInfo.processInfo.environment["TIM_QA_EMAIL_DOMAIN"] ?? "example.com"
        let stamp = Int(Date().timeIntervalSince1970)
        let salt = Int.random(in: 100...999)
        return "tim.qa.\(stamp).\(salt)@\(domain)"
    }()

    private let password = "QaTest-\(Int.random(in: 100_000...999_999))"
    private let fullName = "QA Testing Student"

    /// What the teachers see. It leads with "QA Testing" so nobody takes it.
    private let questionText = "QA Testing - automated test question, please do not accept"

    /// Problems that should fail the run but must not stop it, because the
    /// steps after them are what delete the account. Reported at the very end.
    private var deferredFailures: [String] = []

    /// iOS's own prompts are drawn by other processes; see
    /// `AskQuestionFlowUITests` for why every plausible host is swept.
    private let systemPromptHosts = [
        "com.apple.springboard",
        "com.apple.AuthenticationServicesUI",
        "com.apple.Passwords",
        "com.apple.CredentialSharingService",
        "com.apple.SharedWebCredentialViewService",
    ].map { XCUIApplication(bundleIdentifier: $0) }

    /// Exact labels that turn a system prompt down. The app's own "Not now"
    /// is lower case, so neither label is one of the app's buttons.
    private let promptDismissLabels = ["Not Now", "Don't Allow"]

    override func setUpWithError() throws {
        continueAfterFailure = false

        // The microphone (and, for video, the camera) must be allowed or the
        // question is never sent. Everything else is declined.
        addUIInterruptionMonitor(withDescription: "iOS system prompt") { [promptDismissLabels] alert in
            let text = alert.label + " " + alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            if text.localizedCaseInsensitiveContains("microphone") || text.localizedCaseInsensitiveContains("camera"),
               alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap()
                return true
            }
            for label in promptDismissLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app = XCUIApplication()
        // Keep the tutorial from opening over Home.
        app.launchArguments += ["-tutorial.student.hidden", "YES"]
        app.launch()
    }

    // MARK: - The flow

    @MainActor
    func testSignUpAskLogOutLogInBrowseDeleteThenLoginIsRefused() throws {
        let note = XCTAttachment(string: "email: \(email)")
        note.name = "QA account"
        note.lifetime = .keepAlways
        add(note)
        print("[AccountLifecycleUITests] QA account: \(email)")

        try XCTContext.runActivity(named: "Sign up \(email)") { _ in
            try reachAnonymousHome()
            openSignUpForm()
            signUp()
            finishOnboarding()
        }

        XCTContext.runActivity(named: "Send a QA question and cancel the search") { _ in
            sendQuestionThenCancel()
        }

        XCTContext.runActivity(named: "Log out") { _ in
            logOut()
        }

        try XCTContext.runActivity(named: "Log back in") { _ in
            try reachAnonymousHome()
            openLoginForm()
            submitLogin()
            XCTAssertTrue(
                waitForSignedInHome(timeout: 90),
                "logging back in with the new account did not reach the home screen"
            )
        }

        XCTContext.runActivity(named: "Visit every section of the side menu") { _ in
            browseSideMenuSections()
        }

        XCTContext.runActivity(named: "Delete the account") { _ in
            deleteAccount()
        }

        try XCTContext.runActivity(named: "Log in with the deleted account") { _ in
            try reachAnonymousHome()
            openLoginForm()
            submitLogin()
            assertLoginRefused()
        }

        for failure in deferredFailures {
            XCTFail(failure)
        }
    }

    // MARK: - Getting to a starting point

    /// Brings the app to the home screen of an anonymous student — the only
    /// place in the student app with a way to the login and sign-up forms.
    ///
    /// The simulator may arrive in any state: on the intro, already anonymous,
    /// or signed in to some account left by other work. A signed-in device
    /// looks signed out for a while at launch, so the wait is for one of the
    /// two screens that only appear once the session has been restored.
    @MainActor
    private func reachAnonymousHome() throws {
        let intro = app.buttons["student_intro_start"]
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if intro.exists { break }
            if menuButton.exists {
                openSideMenu()
                if app.buttons["side_menu_log_in"].waitForExistence(timeout: 3) {
                    closeSideMenu()
                    return
                }
                // Signed in to a real account: sign it out first.
                closeSideMenu()
                logOut()
                continue
            }
            pause()
        }

        XCTAssertTrue(tapWhenHittable(intro, "the intro's start button", timeout: 30),
                      "the intro's start button never appeared")
        XCTAssertTrue(menuButton.waitForExistence(timeout: 60),
                      "starting without an account did not reach the home screen")
    }

    @MainActor
    private func openLoginForm() {
        openSideMenu()
        XCTAssertTrue(
            tapWhenHittable(app.buttons["side_menu_log_in"], "the menu's Log in link"),
            "the menu has no Log in link — is this an anonymous session?"
        )
        XCTAssertTrue(app.textFields["email_input"].waitForExistence(timeout: 20),
                      "the login form did not open")
    }

    @MainActor
    private func openSignUpForm() {
        openLoginForm()
        let signUpLink = app.buttons["login_sign_up"]
        scrollIntoView(signUpLink)
        XCTAssertTrue(tapWhenHittable(signUpLink, "the login form's Sign up link"),
                      "the login form's Sign up link was never tappable")
        XCTAssertTrue(app.textFields["sign_up_email"].waitForExistence(timeout: 20),
                      "the sign-up form did not open")
    }

    // MARK: - Sign up

    @MainActor
    private func signUp() {
        type(email, into: app.textFields["sign_up_email"], "the sign-up email field")
        type(password, into: app.secureTextFields["sign_up_password"], "the sign-up password field")
        type(password, into: app.secureTextFields["sign_up_confirm_password"], "the confirm-password field")
        dismissKeyboard()

        let terms = app.buttons["sign_up_terms"]
        scrollIntoView(terms)
        XCTAssertTrue(tapWhenHittable(terms, "the terms check box"), "the terms check box was never tappable")

        let submit = app.buttons["sign_up_continue"]
        scrollIntoView(submit)
        XCTAssertTrue(tapWhenHittable(submit, "the sign-up Continue button"),
                      "the sign-up Continue button was never tappable")
    }

    /// Walks whichever onboarding steps this account is given — profile,
    /// email verification, permissions — until the home screen is up. Which
    /// of them appear depends on Remote Config and on the device, so each is
    /// handled when it shows rather than expected in a fixed order.
    @MainActor
    private func finishOnboarding() {
        var filledProfile = false
        let deadline = Date().addingTimeInterval(150)
        while Date() < deadline {
            if waitForSignedInHome(timeout: 1) { return }

            if signUpErrorIsShowing() {
                return XCTFail("sign-up was refused: \(currentDialogText())")
            }

            let name = app.textFields["complete_profile_full_name"]
            if name.exists && !filledProfile {
                type(fullName, into: name, "the full-name field")
                dismissKeyboard()
                filledProfile = true
            }
            let profileContinue = app.buttons["complete_profile_continue"]
            if profileContinue.exists && profileContinue.isEnabled && filledProfile {
                scrollIntoView(profileContinue)
                _ = tapWhenHittable(profileContinue, "the profile's Continue button", timeout: 5)
                continue
            }

            if tapIfPresent(app.buttons["verify_email_not_now"]) { continue }
            if tapIfPresent(app.buttons["permissions_setup_skip"]) { continue }

            dismissSystemPromptIfPresent(timeout: 1)
        }
        XCTFail("onboarding did not reach the home screen")
    }

    // MARK: - The question

    @MainActor
    private func sendQuestionThenCancel() {
        let field = app.textViews["question_text"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "no question field on the home screen")
        XCTAssertTrue(tapWhenHittable(field, "the question field"), "the question field was never tappable")
        field.typeText(questionText)
        dismissKeyboard()

        let findTeacher = app.buttons["find_teacher"]
        let cancel = app.buttons["search_details_cancel"]

        // The balance arrives with the profile, some seconds after a fresh
        // account reaches home; until then the app says it is checking.
        var outOfMinutes = false
        for _ in 0..<6 {
            guard tapWhenHittable(findTeacher, "Find a teacher") else {
                return XCTFail("the Find a teacher button was never tappable")
            }
            if waitForAny([cancel, app.buttons["not_enough_minutes_primary"], app.buttons["dialog_confirm_button"]],
                          timeout: 20) == nil {
                continue
            }
            if cancel.exists { break }
            if app.buttons["not_enough_minutes_primary"].exists {
                outOfMinutes = true
                _ = tapIfPresent(app.buttons["not_enough_minutes_dismiss"])
                break
            }
            // "Checking your balance": acknowledge and give it a moment.
            _ = tapIfPresent(app.buttons["dialog_confirm_button"])
            pause(seconds: 5)
        }

        guard !outOfMinutes else {
            // Not a reason to stop: the account still has to be deleted.
            deferredFailures.append(
                "the new account has no minutes, so no question could be sent — is the sign-up reward off in Remote Config, or out of slots?"
            )
            return
        }
        guard cancel.exists else {
            deferredFailures.append("Find a teacher never started a search")
            return
        }

        // Long enough for the question to be written and offered, short
        // enough that nobody has time to take it.
        pause(seconds: 4)

        // An audio start can raise the app's own permission card over the
        // search; it is turned down by tapping its scrim, above the card.
        if app.buttons["search_permission_check"].exists {
            if !tapIfPresent(app.buttons["search_permission_not_now"]) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            }
        }

        XCTAssertTrue(tapWhenHittable(cancel, "the search's close button"),
                      "the search's close button was never tappable")
        XCTAssertTrue(waitForDisappearance(cancel, timeout: 20), "cancelling did not end the search")
        XCTAssertTrue(findTeacher.waitForExistence(timeout: 20), "cancelling did not return to the home screen")
    }

    // MARK: - Log out

    @MainActor
    private func logOut() {
        openAccountSecurity()
        let row = app.buttons["settings_row_logOut"]
        XCTAssertTrue(tapWhenHittable(row, "the Log Out row"), "the Log Out row was never tappable")
        XCTAssertTrue(tapWhenHittable(app.buttons["dialog_confirm_button"], "the log-out confirmation"),
                      "the log-out confirmation did not appear")
        XCTAssertTrue(app.buttons["student_intro_start"].waitForExistence(timeout: 60),
                      "logging out did not return to the intro")
    }

    // MARK: - Log in

    @MainActor
    private func submitLogin() {
        type(email, into: app.textFields["email_input"], "the login email field")
        type(password, into: app.secureTextFields["password_input"], "the login password field")
        dismissKeyboard()
        let submit = app.buttons["login_submit"]
        scrollIntoView(submit)
        XCTAssertTrue(tapWhenHittable(submit, "the Log In button"), "the Log In button was never tappable")
    }

    @MainActor
    private func assertLoginRefused() {
        // The refusal is a dialog over the form; a login that went through
        // would instead leave the form for the home screen.
        let refusal = app.buttons["dialog_confirm_button"]
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if refusal.exists { break }
            if app.buttons["find_teacher"].exists && !app.textFields["email_input"].exists {
                return XCTFail("the deleted account could still log in")
            }
            dismissSystemPromptIfPresent(timeout: 1)
        }
        XCTAssertTrue(refusal.exists, "logging in with the deleted account raised no error")
        let message = currentDialogText()
        XCTContext.runActivity(named: "Refusal: \(message)") { _ in }
        _ = tapWhenHittable(refusal, "the error's OK button", timeout: 10)
        XCTAssertTrue(app.textFields["email_input"].waitForExistence(timeout: 10),
                      "the login form is gone after a refused login")
        XCTAssertFalse(app.buttons["find_teacher"].isHittable,
                       "the home screen is reachable after a refused login")
    }

    // MARK: - Side menu sections

    @MainActor
    private func browseSideMenuSections() {
        // Help opens the support screen; Ask returns home last, so the next
        // step starts from a known screen.
        for section in ["activity", "profile", "help", "settings", "ask"] {
            openSideMenu()
            let item = app.buttons["side_menu_item_\(section)"]
            XCTAssertTrue(tapWhenHittable(item, "the \(section) menu row"),
                          "the side menu has no \(section) row")
            XCTAssertTrue(waitForDisappearance(app.buttons["side_menu_close"]),
                          "the side menu did not close after picking \(section)")
            if section == "settings" {
                XCTAssertTrue(app.buttons["settings_row_accountSecurity"].waitForExistence(timeout: 15),
                              "Settings did not open")
            }
            // Help & Support can open in a sheet with its own close button.
            _ = tapIfPresent(app.buttons["brand_sheet_close"])
            XCTAssertTrue(menuButton.waitForExistence(timeout: 15),
                          "the \(section) section has no way back to the menu")
        }
        XCTAssertTrue(app.buttons["find_teacher"].waitForExistence(timeout: 15),
                      "Ask did not return to the home screen")
    }

    // MARK: - Delete the account

    @MainActor
    private func deleteAccount() {
        openAccountSecurity()
        let row = app.buttons["settings_row_deleteAccount"]
        scrollIntoView(row)
        XCTAssertTrue(tapWhenHittable(row, "the Delete Account row"), "the Delete Account row was never tappable")

        // First "this cannot be undone", then the password.
        XCTAssertTrue(tapWhenHittable(app.buttons["dialog_confirm_button"], "the delete confirmation"),
                      "the delete confirmation did not appear")
        let passwordField = app.secureTextFields["dialog_secure_input"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 20), "deleting did not ask for the password")
        type(password, into: passwordField, "the delete dialog's password field")
        XCTAssertTrue(tapWhenHittable(app.buttons["dialog_confirm_button"], "the dialog's Delete button"),
                      "the dialog's Delete button was never tappable")

        let intro = app.buttons["student_intro_start"]
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline && !intro.exists {
            if app.buttons["dialog_confirm_button"].exists && !passwordField.exists {
                return XCTFail("deleting the account failed: \(currentDialogText())")
            }
            pause()
        }
        XCTAssertTrue(intro.exists, "deleting the account did not return to the intro")
    }

    @MainActor
    private func openAccountSecurity() {
        openSideMenu()
        XCTAssertTrue(tapWhenHittable(app.buttons["side_menu_item_settings"], "the menu's Settings row"),
                      "the menu's Settings row was never tappable")
        let accountSecurity = app.buttons["settings_row_accountSecurity"]
        XCTAssertTrue(accountSecurity.waitForExistence(timeout: 15), "Settings did not open")
        XCTAssertTrue(tapWhenHittable(accountSecurity, "the Account & Security row"),
                      "the Account & Security row was never tappable")
        XCTAssertTrue(app.buttons["settings_row_logOut"].waitForExistence(timeout: 15),
                      "Account & Security did not open")
    }

    // MARK: - Side menu

    private var menuButton: XCUIElement {
        app.buttons["side_menu_button"]
    }

    @MainActor
    private func openSideMenu() {
        XCTAssertTrue(tapWhenHittable(menuButton, "the side-menu button"),
                      "the side-menu button was never tappable")
        XCTAssertTrue(app.buttons["side_menu_close"].waitForExistence(timeout: 10),
                      "the side menu did not open")
    }

    @MainActor
    private func closeSideMenu() {
        _ = tapWhenHittable(app.buttons["side_menu_close"], "the side menu's close button", timeout: 10)
        _ = waitForDisappearance(app.buttons["side_menu_close"])
    }

    // MARK: - Screens

    /// The signed-in home: the question field is up and no onboarding step is.
    @MainActor
    private func waitForSignedInHome(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.buttons["find_teacher"].exists && menuButton.exists
                && !app.textFields["email_input"].exists {
                return true
            }
            if timeout > 1 { dismissSystemPromptIfPresent(timeout: 1) }
        } while Date() < deadline
        return false
    }

    private func signUpErrorIsShowing() -> Bool {
        app.textFields["sign_up_email"].exists && app.buttons["dialog_confirm_button"].exists
    }

    /// Every text in the dialog on screen, for a failure message.
    private func currentDialogText() -> String {
        app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty }
            .suffix(4)
            .joined(separator: " / ")
    }

    // MARK: - Input

    @MainActor
    private func type(_ text: String, into field: XCUIElement, _ described: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 20), "no \(described)")
        scrollIntoView(field)
        XCTAssertTrue(tapWhenHittable(field, described), "\(described) was never tappable")
        field.typeText(text)
    }

    @MainActor
    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        // Return on the keyboard moves focus or submits on some fields, so
        // the keyboard is lowered by tapping clear of every control instead.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        _ = waitForDisappearance(app.keyboards.firstMatch, timeout: 3)
    }

    @MainActor
    private func scrollIntoView(_ element: XCUIElement) {
        guard element.waitForExistence(timeout: 10) else { return }
        for _ in 0..<4 where !element.isHittable {
            app.swipeUp()
        }
    }

    // MARK: - System prompts

    @MainActor
    @discardableResult
    private func dismissSystemPromptIfPresent(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let hosts: [XCUIApplication] = systemPromptHosts + [app]
        repeat {
            for host in hosts {
                for label in promptDismissLabels {
                    let button = host.buttons[label]
                    if button.exists && button.isHittable {
                        button.tap()
                        return true
                    }
                }
            }
            pause()
        } while Date() < deadline
        return false
    }

    /// Taps once nothing covers the element, clearing system prompts while
    /// waiting: `tap()` on a covered element fails the test outright.
    @MainActor
    private func tapWhenHittable(
        _ element: XCUIElement,
        _ described: String,
        timeout: TimeInterval = 30
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
            if !dismissSystemPromptIfPresent(timeout: 1) {
                pause()
            }
        } while Date() < deadline
        return false
    }

    @MainActor
    private func tapIfPresent(_ element: XCUIElement) -> Bool {
        guard element.exists && element.isHittable else { return false }
        element.tap()
        return true
    }

    // MARK: - Waiting

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let found = elements.first(where: \.exists) { return found }
            pause()
        } while Date() < deadline
        return nil
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline {
            pause()
        }
        return !element.exists
    }

    private func pause(seconds: TimeInterval = 1) {
        _ = XCTWaiter.wait(for: [expectation(description: "poll")], timeout: seconds)
    }
}
