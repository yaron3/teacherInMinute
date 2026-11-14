//
//  SignUpValidationUITests.swift
//  TeacherMinuteUITests
//
//  IT-20: when the sign-up form has several mistakes, one alert lists all of
//  them at once, instead of only the email error until it is fixed.
//
//  Nothing here reaches the backend: every rule fails on the device, so no
//  account is created and no emulator is needed.
//

import XCTest

final class SignUpValidationUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // The emulator flags only route the sign-out that starts the test from
        // the welcome screen; the sign-out itself is local, so no emulator needs
        // to be running.
        app.launchArguments += ["-firebaseEmulatorHost", EmulatorBackend.host, "-firebaseEmulatorSignOut", "YES"]
        app.launch()
    }

    @MainActor
    func testEveryFailingSignUpRuleIsReportedTogether() throws {
        openSignUpForm()

        typeText("not-an-email", into: app.textFields["sign_up_email"])
        typeSecure("123456", into: app.secureTextFields["sign_up_password"])
        typeSecure("654321", into: app.secureTextFields["sign_up_confirm_password"])
        dismissKeyboard()

        tapContinue()

        let alertText = waitForAlertText(containing: "valid email")
        XCTAssertTrue(alertText.contains("valid email"), "the email error is missing: \(alertText)")
        XCTAssertTrue(alertText.contains("do not match"), "the password mismatch is missing from the same alert: \(alertText)")
        keep("IT-20 sign-up, email and password both wrong")
    }

    // MARK: - Helpers

    @MainActor
    private func openSignUpForm() {
        let emailField = app.textFields["sign_up_email"]
        // A fresh launch can open on the intro, whose "Get started" leads to
        // the welcome screen and its Sign up.
        let getStarted = app.buttons["Get started"]
        for _ in 0..<5 where !emailField.exists {
            let signUp = app.buttons["welcome_sign_up"]
            if signUp.waitForExistence(timeout: 5) {
                signUp.tap()
            } else if getStarted.exists {
                getStarted.tap()
            } else {
                keep("IT-20 launch state, neither intro nor welcome")
                XCTFail("neither the intro nor the welcome screen appeared")
                return
            }
            _ = emailField.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(emailField.exists, "the sign-up form did not open")
    }

    @MainActor
    private func typeText(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no field for \(text)")
        field.tap()
        field.typeText(text)
    }

    @MainActor
    private func typeSecure(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no secure field for \(text)")
        field.tap()
        field.typeText(text)
    }

    @MainActor
    private func dismissKeyboard() {
        if app.keyboards.count > 0 {
            app.toolbars.buttons.firstMatch.tap()
        }
    }

    @MainActor
    private func tapContinue() {
        let button = app.buttons["sign_up_continue"]
        for _ in 0..<5 where !button.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no sign-up Continue")
        button.tap()
    }

    /// The alert's message text, once it shows a line containing `needle`.
    @MainActor
    private func waitForAlertText(containing needle: String) -> String {
        let deadline = Date().addingTimeInterval(10)
        var collected = ""
        while Date() < deadline {
            collected = app.staticTexts.allElementsBoundByIndex
                .compactMap { $0.label }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if collected.contains(needle) { return collected }
            usleep(200_000)
        }
        return collected
    }

    @MainActor
    private func keep(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
