//
//  SignUpValidationUITests.swift
//  TeacherMinuteUITests
//
//  IT-20: when the sign-up form has several mistakes, all of them are
//  reported at once, instead of only the email error until it is fixed.
//
//  Since the QA-sheet fixes of 4d484eb (AND-T-12 / Bug-007) the form reports
//  them inline, each under its own field, and keeps Continue off until the
//  form is right; there is no dialog any more. So this checks that the email
//  error and the password mismatch show together, with Continue off.
//
//  Every rule fails on the device, so no account is created. The app may
//  start a guest session on launch, though, which is why it is pointed at the
//  emulators.
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

        // Either language: the app may have Remote Config's Hebrew cached.
        let screen = waitForScreenText(containingAnyOf: ["do not match", "אינן תואמות"])
        keep("IT-20 sign-up, email and password both wrong")
        XCTAssertTrue(["valid email", "כתובת אימייל תקינה"].contains { screen.contains($0) },
                      "the email error is missing: \(screen)")
        XCTAssertTrue(["do not match", "אינן תואמות"].contains { screen.contains($0) },
                      "the password mismatch is not shown with the email error: \(screen)")
        let continueButton = app.buttons["sign_up_continue"]
        for _ in 0..<5 where !continueButton.isHittable { app.swipeUp() }
        XCTAssertTrue(continueButton.exists, "no sign-up Continue")
        XCTAssertFalse(continueButton.isEnabled, "Continue is on with a wrong form")
    }

    // MARK: - Helpers

    @MainActor
    private func openSignUpForm() {
        let emailField = app.textFields["sign_up_email"]
        // A fresh launch can open on the intro, whose "Get started" leads to
        // the welcome screen and its Sign up — or straight on a guest's home,
        // whose menu has Log in, and the login form Sign up.
        let getStarted = app.buttons["Get started"]
        let menu = app.buttons["side_menu_button"]
        for _ in 0..<5 where !emailField.exists {
            let signUp = app.buttons["welcome_sign_up"]
            if signUp.waitForExistence(timeout: 5) {
                signUp.tap()
            } else if getStarted.exists {
                getStarted.tap()
            } else if menu.exists {
                openSignUpFromGuestHome(menu)
            } else {
                keep("IT-20 launch state, neither intro nor welcome")
                XCTFail("neither the intro nor the welcome screen appeared")
                return
            }
            _ = emailField.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(emailField.exists, "the sign-up form did not open")
    }

    /// Menu → Log in → the login form's Sign up.
    @MainActor
    private func openSignUpFromGuestHome(_ menu: XCUIElement) {
        menu.tap()
        let logIn = app.buttons["side_menu_log_in"]
        guard logIn.waitForExistence(timeout: 10) else {
            keep("IT-20 guest menu without Log in")
            XCTFail("the guest's menu has no Log in")
            return
        }
        logIn.tap()
        let signUpLink = app.buttons["login_sign_up"]
        guard signUpLink.waitForExistence(timeout: 20) else {
            XCTFail("the login form has no Sign up link")
            return
        }
        for _ in 0..<5 where !signUpLink.isHittable { app.swipeUp() }
        signUpLink.tap()
    }

    @MainActor
    private func typeText(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no field for \(text)")
        field.tap()
        field.typeText(text)
    }

    /// iOS's "Use Strong Password?" sheet comes up over a sign-up password
    /// field on a tap and swallows what is typed; closed first, as in
    /// AccountLifecycleUITests.
    @MainActor
    private func typeSecure(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no secure field for \(text)")
        for _ in 0..<3 {
            _ = closeStrongPasswordSheet(wait: 0.5)
            if !field.isHittable { app.swipeUp() }
            field.tap()
            if !closeStrongPasswordSheet() { break }
        }
        field.typeText(text)
        _ = closeStrongPasswordSheet(wait: 0.5)
    }

    /// Closes the strong-password sheet if it is up; true when it was.
    @MainActor
    private func closeStrongPasswordSheet(wait: TimeInterval = 2) -> Bool {
        let hosts = [
            app!,
            XCUIApplication(bundleIdentifier: "com.apple.springboard"),
            XCUIApplication(bundleIdentifier: "com.apple.AuthenticationServicesUI"),
            XCUIApplication(bundleIdentifier: "com.apple.Passwords"),
            XCUIApplication(bundleIdentifier: "com.apple.CredentialSharingService"),
        ].filter { $0.state != .notRunning }
        let deadline = Date().addingTimeInterval(wait)
        repeat {
            for host in hosts {
                for label in ["xmark", "Close", "Choose My Own Password", "Not Now"] {
                    let button = host.buttons[label]
                    if button.exists && button.isHittable {
                        button.tap()
                        usleep(500_000)
                        return true
                    }
                }
            }
            usleep(250_000)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        // The form has no keyboard toolbar, and Return moves focus on: the
        // keyboard is lowered by tapping clear of every control, as in
        // AccountLifecycleUITests.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        let deadline = Date().addingTimeInterval(3)
        while app.keyboards.firstMatch.exists && Date() < deadline { usleep(200_000) }
    }

    /// Every text on screen, once one of `needles` shows (or after 10 s).
    @MainActor
    private func waitForScreenText(containingAnyOf needles: [String]) -> String {
        let deadline = Date().addingTimeInterval(10)
        var collected = ""
        while Date() < deadline {
            // One snapshot of the whole screen: reading the texts one by one
            // races the form's updates, and an element counted a moment
            // earlier can be gone by the time it is read.
            if let snapshot = try? app.snapshot() {
                collected = Self.labels(in: snapshot).joined(separator: "\n")
                if needles.contains(where: { collected.contains($0) }) { return collected }
            }
            usleep(200_000)
        }
        return collected
    }

    /// Every non-empty static text label in the snapshot, depth first.
    private static func labels(in snapshot: XCUIElementSnapshot) -> [String] {
        let own = snapshot.elementType == .staticText && !snapshot.label.isEmpty ? [snapshot.label] : []
        return own + snapshot.children.flatMap { labels(in: $0) }
    }

    @MainActor
    private func keep(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
