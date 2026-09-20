//
//  AskQuestionFlowUITests.swift
//  TeacherMinuteUITests
//
//  Signs in, checks the home screen, writes a question and uses the algebra
//  keyboard.
//
//  Every label is looked up in both English and Hebrew: the app's language is
//  an account preference rather than a device setting, so a test that knows
//  only one of them passes or fails depending on who last used the simulator.
//
//  The flow stops before the question is sent, on purpose. Dispatch fans a
//  question out to every online teacher covering its topic, so a test must
//  never submit one — see the project's CLAUDE.md.
//

import XCTest

final class AskQuestionFlowUITests: XCTestCase {

    /// Credentials for the test account. Overridable so a CI machine can use
    /// its own without editing the test.
    private var email: String {
        ProcessInfo.processInfo.environment["TIM_TEST_EMAIL"] ?? "s1@a.com"
    }

    private var password: String {
        ProcessInfo.processInfo.environment["TIM_TEST_PASSWORD"] ?? "123456"
    }

    private var app: XCUIApplication!

    /// iOS's own prompts are drawn by other processes, so they are reached
    /// through their own application objects rather than through `app`. Which
    /// process hosts the "Save Password?" sheet is a private detail that has
    /// moved between releases, so every plausible host is swept.
    private let systemPromptHosts = [
        "com.apple.springboard",
        "com.apple.AuthenticationServicesUI",
        "com.apple.Passwords",
        "com.apple.CredentialSharingService",
        "com.apple.SharedWebCredentialViewService",
    ].map { XCUIApplication(bundleIdentifier: $0) }

    /// Buttons that dismiss a system prompt without agreeing to anything.
    ///
    /// Deliberately not "Cancel": the sweep below looks through the app as
    /// well as the system hosts, and the app has its own Cancel buttons — the
    /// ask-a-teacher screen among them. These two labels appear on no screen
    /// of the app. Its own "Not now" is lower case, and the match is exact.
    private let promptDismissLabels = ["Not Now", "Don't Allow"]

    // MARK: - Labels
    //
    // Every value here is the English string the app ships paired with the
    // Hebrew from `backend/Firebase/remote_config_tim.json`.

    private let authLabels = ["Welcome Back", "Log In", "ברוך השב", "התחבר"]
    private let logInLabels = ["Log In", "התחבר"]
    private let settingsLabels = ["Settings", "הגדרות"]
    private let accountSecurityLabels = ["Account & Security", "חשבון ואבטחה"]
    private let logOutLabels = ["Log Out", "התנתק"]
    private let studentHomeLabels = ["Ask a question now", "שאל שאלה עכשיו"]
    private let questionSectionLabels = ["Your question", "השאלה שלך"]
    /// The two dialogs the app raises instead of opening the ask screen. The
    /// first means the balance has not arrived yet, the second that it has and
    /// is short — on a cold start the first is what a fast tap gets.
    private let balanceLoadingLabels = ["Checking your balance", "בודקים את היתרה שלך"]
    private let lowBalanceLabels = ["Low Balance", "יתרה נמוכה"]

    /// How long to let a saved session restore before concluding that there is
    /// none. Long enough to cover a cold launch on a busy machine, since
    /// concluding too early runs the whole flow against the wrong account.
    private let sessionRestoreTimeout: TimeInterval = 45

    override func setUpWithError() throws {
        continueAfterFailure = false

        // The documented route for a prompt that lands mid-flow: XCTest calls
        // this when an interaction is blocked by another process's alert, and
        // retries the interaction once the handler reports it dealt with one.
        // The sweep below covers the window where the test is only waiting,
        // when there is no interaction for this to hang off.
        addUIInterruptionMonitor(withDescription: "iOS system prompt") { [promptDismissLabels] alert in
            for label in promptDismissLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app = XCUIApplication()
        app.launch()
    }

    // MARK: - The flow

    @MainActor
    func testSignInThenWriteAQuestionWithTheAlgebraKeyboard() throws {
        try signInIfNeeded()
        assertHomeScreen()
        openAskATeacher()
        writeQuestionText()
        useAlgebraKeyboard()
    }

    // MARK: - Steps

    @MainActor
    private func signInIfNeeded() throws {
        // The test runs on a clone of the destination simulator, app data
        // included, so the app may open on whatever account that device was
        // last used with — which, on a machine that also takes the App Store
        // screenshots, is as likely to be a teacher as a student.
        //
        // Which it is cannot be read off the first screen: the app shows the
        // welcome screen while it restores a saved session, so a check made at
        // launch calls every signed-in device signed out. The tab bar is the
        // tell — both roles draw one, and the auth screens do not — so the
        // wait is for that, and only its absence means nobody is signed in.
        if waitForAny(settingsLabels, timeout: sessionRestoreTimeout) {
            // Sign out, so the test covers the sign-in it claims to cover and
            // runs the rest of the flow as its own account.
            signOut()
        }

        XCTAssertTrue(
            waitForAny(authLabels, timeout: 60),
            "neither the welcome screen nor the sign-in form appeared"
        )

        // The welcome screen offers sign-up and sign-in; the form itself is
        // the one with a password field.
        if let logIn = element(anyOf: logInLabels, in: app.buttons),
           !app.secureTextFields.firstMatch.exists {
            logIn.tap()
        }

        let emailField = field(app.textFields, identifier: "email_input")
        XCTAssertTrue(emailField.waitForExistence(timeout: 20), "no email field on the sign-in form")
        emailField.tap()
        emailField.typeText(email)

        let passwordField = field(app.secureTextFields, identifier: "password_input")
        XCTAssertTrue(passwordField.waitForExistence(timeout: 10), "no password field on the sign-in form")
        passwordField.tap()
        passwordField.typeText(password)

        guard let submit = element(anyOf: logInLabels, in: app.buttons) else {
            return XCTFail("no sign-in button")
        }
        submit.tap()

        XCTAssertTrue(
            waitForAny(studentHomeLabels, timeout: 90),
            "signing in did not reach the home screen"
        )

        dismissSystemPromptIfPresent()
    }

    @MainActor
    private func assertHomeScreen() {
        assertVisible(studentHomeLabels, "the ask-a-question button")
        assertVisible(["Total minutes", "סך כל הדקות"], "the minutes balance")
        assertVisible(["Available Subjects", "מקצועות זמינים"], "the subjects section")
        assertVisible(["How it works", "איך זה עובד"], "the how-it-works panel")

        // The tab bar, which is also where a missing icon shows up first.
        for tab in [["Home", "בית"], ["Lessons", "שיעורים"], ["Profile", "פרופיל"], settingsLabels] {
            XCTAssertNotNil(
                element(anyOf: tab, in: app.buttons) ?? element(anyOf: tab, in: app.staticTexts),
                "the \(tab[0]) tab is missing from the tab bar"
            )
        }
    }

    @MainActor
    private func openAskATeacher() {
        // Two things can stand between this tap and the ask screen, and both
        // are about timing rather than about the app being wrong:
        //
        //  - iOS's "Save Password?" prompt, which lands some time after a
        //    sign-in and takes the tap instead of the app;
        //  - the app's own Low Balance dialog, which it raises when the tap
        //    beats the profile load and the balance still reads zero.
        //
        // Both are cleared and the tap retried, so the test does not depend on
        // how long a cold start takes on the machine it runs on.
        var sawBalanceDialog = false
        for _ in 0..<6 {
            if isOnScreen(balanceLoadingLabels) || isOnScreen(lowBalanceLabels) {
                sawBalanceDialog = true
                let acknowledge = app.buttons["dialog_confirm_button"]
                _ = tapWhenHittable(acknowledge, "the balance dialog's OK button", timeout: 10)
                // Give the profile the time the dialog says it needs.
                pause()
                pause()
            }

            guard let ask = element(anyOf: studentHomeLabels, in: app.buttons)
                ?? element(anyOf: studentHomeLabels, in: app.staticTexts) else {
                return XCTFail("no ask-a-question button on the home screen")
            }
            guard tapWhenHittable(ask, "the ask-a-question button") else { continue }

            if waitForAny(questionSectionLabels, timeout: 10) { break }
        }

        XCTAssertTrue(
            isOnScreen(questionSectionLabels),
            sawBalanceDialog
                ? "the ask-a-teacher screen did not open: the app kept answering with a balance dialog, so \(email) is out of minutes or its profile never loaded"
                : "the ask-a-teacher screen did not open"
        )
        assertVisible(["Session type", "סוג שיעור"], "the session type section")
        assertVisible(["Topic", "נושא"], "the topic section")
        assertVisible(["Attach a photo", "צירוף תמונה"], "the photo section")
    }

    @MainActor
    private func writeQuestionText() {
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 20), "no question field on the screen")
        if !editor.hasKeyboardFocus {
            XCTAssertTrue(
                tapWhenHittable(editor, "the question field"),
                "the question field never became tappable"
            )
        }
        let question = "How do I solve this equation"
        editor.typeText(question)
        XCTAssertTrue(
            app.textViews.containing(NSPredicate(format: "value CONTAINS %@", question)).firstMatch.exists
                || editor.value as? String == question,
            "the question text did not reach the field"
        )
    }

    @MainActor
    private func useAlgebraKeyboard() {
        // By identifier, not by label: "Algebra" is also a topic chip on this
        // screen, and the chip comes first in the hierarchy.
        let algebra = app.buttons["keyboard_mode_algebra"]
        XCTAssertTrue(algebra.waitForExistence(timeout: 20), "no algebra keyboard switch on the screen")
        XCTAssertTrue(
            tapWhenHittable(algebra, "the algebra keyboard switch"),
            "the algebra keyboard switch never became tappable"
        )

        XCTAssertTrue(waitForAny(["Clear", "π"], timeout: 20), "the algebra pad did not appear")
        for key in ["x²", "√", "π"] {
            assertVisible([key], "the \(key) key")
        }

        for key in ["7", "+", "3"] {
            element(anyOf: [key], in: app.buttons)?.tap()
        }

        let regular = app.buttons["keyboard_mode_regular"]
        XCTAssertTrue(regular.exists, "no regular keyboard switch on the screen")
        XCTAssertTrue(
            tapWhenHittable(regular, "the regular keyboard switch"),
            "the regular keyboard switch never became tappable"
        )
        XCTAssertFalse(
            element(anyOf: ["Clear"], in: app.buttons)?.exists ?? false,
            "the algebra pad is still on screen after switching back"
        )
        // The question is deliberately left unsent.
    }

    // MARK: - Signing out

    @MainActor
    private func signOut() {
        // Log Out is not on the Settings root: it lives one level down, under
        // Account & Security, next to Delete Account — so each step is waited
        // for rather than tapped blind.
        tapElement(anyOf: settingsLabels, "the Settings tab")

        // ACCOUNT is the last section of a scrolling settings list, and
        // SwiftUI builds a List's rows lazily: a row below the fold is absent
        // from the tree rather than merely off-screen, so waiting for one
        // without scrolling never ends.
        scrollUntilVisible(accountSecurityLabels, "the Account & Security row")
        tapElement(anyOf: accountSecurityLabels, "the Account & Security row")

        scrollUntilVisible(logOutLabels, "the Log Out row")
        tapElement(anyOf: logOutLabels, "the Log Out row")

        // The confirmation reuses the row's wording, so it is taken by
        // identifier — by label there is no telling the two apart.
        let confirm = app.buttons["dialog_confirm_button"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), "the log-out confirmation did not appear")
        confirm.tap()

        XCTAssertTrue(
            waitForAny(authLabels, timeout: 60),
            "signing out did not return to the sign-in screen"
        )
    }

    // MARK: - System prompts

    /// Dismisses a system prompt if one is up — in practice the "Save
    /// Password?" sheet iOS offers just after a sign-in. It sits over the app
    /// and takes the next tap, which makes the step after it look as though
    /// the app never responded.
    ///
    /// Returns whether it dismissed anything, so a caller can tell a cleared
    /// prompt from a screen that is simply slow.
    ///
    /// The project leaves the simulator's own language alone, so these buttons
    /// keep their English labels whichever language the app is in.
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

    /// Taps an element once nothing is covering it, clearing system prompts
    /// while it waits.
    ///
    /// The waiting has to happen *before* the tap rather than be retried
    /// after: `tap()` on a covered element fails the test outright, it does
    /// not simply miss. And the prompt cannot be cleared once up-front either,
    /// because iOS raises it on its own schedule — several seconds after a
    /// sign-in, which is exactly the gap between the home screen appearing and
    /// this tap.
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

    // MARK: - Helpers

    /// The field with this identifier, falling back to the first of its kind
    /// on screen for a form that has not been given one.
    private func field(_ query: XCUIElementQuery, identifier: String) -> XCUIElement {
        let identified = query[identifier]
        return identified.exists ? identified : query.firstMatch
    }

    private func element(anyOf labels: [String], in query: XCUIElementQuery) -> XCUIElement? {
        for label in labels {
            let match = query.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
            if match.exists { return match }
        }
        return nil
    }

    /// Taps the first element carrying one of these labels, looking through
    /// the queries a SwiftUI row can surface as. A row that reports itself as
    /// unhittable — a list row with no hit region of its own — is tapped at
    /// its centre instead of being skipped.
    @MainActor
    private func tapElement(anyOf labels: [String], _ described: String) {
        let queries = [app.buttons, app.cells, app.staticTexts, app.otherElements]
        for query in queries {
            if let match = element(anyOf: labels, in: query), match.isHittable {
                match.tap()
                return
            }
        }
        for query in queries {
            if let match = element(anyOf: labels, in: query) {
                match.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                return
            }
        }
        XCTFail("could not tap \(described)")
    }

    /// Whether any of these labels is in the accessibility tree right now.
    private func isOnScreen(_ labels: [String]) -> Bool {
        element(anyOf: labels, in: app.staticTexts) != nil
            || element(anyOf: labels, in: app.buttons) != nil
            || element(anyOf: labels, in: app.cells) != nil
    }

    private func waitForAny(_ labels: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isOnScreen(labels) { return true }
            pause()
        }
        return false
    }

    /// Scrolls until one of these labels is on screen, for a row a lazy List
    /// has not built yet.
    @MainActor
    private func scrollUntilVisible(_ labels: [String], _ described: String, swipes: Int = 8) {
        // Let the screen arrive before deciding that it needs scrolling.
        if waitForAny(labels, timeout: 5) { return }
        for _ in 0..<swipes {
            app.swipeUp()
            if isOnScreen(labels) { return }
        }
        XCTFail("\(described) never came into view")
    }

    /// One second of doing nothing, for the polling loops above.
    private func pause() {
        _ = XCTWaiter.wait(for: [expectation(description: "poll")], timeout: 1)
    }

    private func assertVisible(_ labels: [String], _ described: String) {
        let found = element(anyOf: labels, in: app.staticTexts) != nil
            || element(anyOf: labels, in: app.buttons) != nil
        XCTAssertTrue(found, "\(described) is not on screen")
    }
}

private extension XCUIElement {
    /// Whether this element currently holds the keyboard, so a test does not
    /// tap a field that is already focused and move the caret.
    var hasKeyboardFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}
