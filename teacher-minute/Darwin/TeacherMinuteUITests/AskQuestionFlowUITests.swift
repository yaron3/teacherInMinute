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

    override func setUpWithError() throws {
        continueAfterFailure = false
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
        if waitForAny(["Ask a question now", "שאל שאלה עכשיו"], timeout: 60) {
            // Already signed in from an earlier run. Sign out so the test
            // covers the sign-in it claims to cover.
            signOut()
        }

        XCTAssertTrue(
            waitForAny(["Welcome Back", "Log In", "ברוך", "התחבר"], timeout: 60),
            "neither the welcome screen nor the sign-in form appeared"
        )

        if let logIn = element(anyOf: ["Log In", "התחבר"], in: app.buttons),
           !app.secureTextFields.firstMatch.exists {
            logIn.tap()
        }

        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 20), "no email field on the sign-in form")
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields.firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 10), "no password field on the sign-in form")
        passwordField.tap()
        passwordField.typeText(password)

        guard let submit = element(anyOf: ["Log In", "התחבר"], in: app.buttons) else {
            return XCTFail("no sign-in button")
        }
        submit.tap()

        XCTAssertTrue(
            waitForAny(["Ask a question now", "שאל שאלה עכשיו"], timeout: 90),
            "signing in did not reach the home screen"
        )
    }

    @MainActor
    private func assertHomeScreen() {
        assertVisible(["Ask a question now", "שאל שאלה עכשיו"], "the ask-a-question button")
        assertVisible(["Total minutes", "סך כל הדקות"], "the minutes balance")
        assertVisible(["Available Subjects", "מקצועות זמינים"], "the subjects section")
        assertVisible(["How it works", "איך זה עובד"], "the how-it-works panel")

        // The tab bar, which is also where a missing icon shows up first.
        for tab in [["Home", "בית"], ["Lessons", "שיעורים"], ["Profile", "פרופיל"], ["Settings", "הגדרות"]] {
            XCTAssertNotNil(
                element(anyOf: tab, in: app.buttons) ?? element(anyOf: tab, in: app.staticTexts),
                "the \(tab[0]) tab is missing from the tab bar"
            )
        }
    }

    @MainActor
    private func openAskATeacher() {
        guard let ask = element(anyOf: ["Ask a question now", "שאל שאלה עכשיו"], in: app.buttons)
            ?? element(anyOf: ["Ask a question now", "שאל שאלה עכשיו"], in: app.staticTexts) else {
            return XCTFail("no ask-a-question button on the home screen")
        }
        ask.tap()

        XCTAssertTrue(
            waitForAny(["Your question", "השאלה שלך"], timeout: 30),
            "the ask-a-teacher sheet did not open"
        )
        assertVisible(["Session type", "סוג שיעור"], "the session type section")
        assertVisible(["Topic", "נושא"], "the topic section")
        assertVisible(["Attach a photo", "צירוף תמונה"], "the photo section")
    }

    @MainActor
    private func writeQuestionText() {
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 20), "no question field on the sheet")
        if !editor.hasKeyboardFocus {
            editor.tap()
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
        guard let algebra = element(anyOf: ["Algebra", "אלגברה"], in: app.buttons) else {
            return XCTFail("no algebra keyboard switch on the sheet")
        }
        algebra.tap()

        XCTAssertTrue(waitForAny(["Clear", "π"], timeout: 20), "the algebra pad did not appear")
        for key in ["x²", "√", "π"] {
            assertVisible([key], "the \(key) key")
        }

        for key in ["7", "+", "3"] {
            element(anyOf: [key], in: app.buttons)?.tap()
        }

        guard let regular = element(anyOf: ["Regular", "רגיל"], in: app.buttons) else {
            return XCTFail("no regular keyboard switch on the sheet")
        }
        regular.tap()
        XCTAssertFalse(
            element(anyOf: ["Clear"], in: app.buttons)?.exists ?? false,
            "the algebra pad is still on screen after switching back"
        )
        // The question is deliberately left unsent.
    }

    @MainActor
    private func signOut() {
        element(anyOf: ["Settings", "הגדרות"], in: app.buttons)?.tap()
        let logOut = element(anyOf: ["Log Out", "התנתק"], in: app.buttons)
            ?? element(anyOf: ["Log Out", "התנתק"], in: app.staticTexts)
        logOut?.tap()
        // The confirmation reuses the same wording as the row that opened it.
        element(anyOf: ["Log Out", "התנתק"], in: app.buttons)?.tap()
        _ = waitForAny(["Welcome Back", "Log In", "ברוך", "התחבר"], timeout: 30)
    }

    // MARK: - Helpers

    private func element(anyOf labels: [String], in query: XCUIElementQuery) -> XCUIElement? {
        for label in labels {
            let match = query.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
            if match.exists { return match }
        }
        return nil
    }

    private func waitForAny(_ labels: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let predicate = NSPredicate(format: "label CONTAINS[c] %@", label)
                if app.staticTexts.matching(predicate).firstMatch.exists
                    || app.buttons.matching(predicate).firstMatch.exists {
                    return true
                }
            }
            _ = XCTWaiter.wait(for: [expectation(description: "poll")], timeout: 1)
        }
        return false
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
