//
//  ProTeacherSignUpUITests.swift
//  TeacherMinuteUITests
//
//  Pro Teacher's sign-up and onboarding, against the real backend on the
//  local Firebase emulators. QA test plan:
//
//   IOS-T-01  email sign-up through every onboarding step reaches the
//             dashboard: one new Auth user (password), users/{uid}.role
//             teacher, with the name and phone typed
//   IOS-T-05  with teacher_identity_onboarding off — its default, and the
//             emulators have no Remote Config — sign-up goes straight to the
//             profile, with no ID step
//   IOS-T-06  subjects: none cannot continue; two are saved
//   IOS-T-07  the profile cannot be finished without a name and a valid phone
//   IOS-T-10  killed on the profile step, the app resumes there
//   IOS-T-11  an address already in use is refused, with no second user
//   IOS-T-12  a bad address, a short password, a mismatched confirmation or
//             unaccepted terms are each refused, and nothing is created
//   IOS-T-13  a student account is turned away with the other app's notice,
//             signed out, its role untouched
//
//  Setup and running are as for ProTeacherAcceptRaceUITests.
//

import XCTest

final class ProTeacherSignUpUITests: ProTeacherEmulatorTestCase {

    /// "This email address is already in use.", in either language.
    private let inUseMessages = ["This email address is already in use.", "כתובת המייל הזו כבר רשומה במערכת."]
    private var nameField: XCUIElement { app.textFields["complete_profile_full_name"] }
    private var phoneField: XCUIElement { app.textFields["complete_profile_phone"] }
    private var profileContinue: XCUIElement { app.buttons["complete_profile_continue"] }

    /// IOS-T-01 and IOS-T-05: an email sign-up, through the profile, to the
    /// dashboard.
    @MainActor
    func testEmailSignUpReachesTheDashboard() async throws {
        try await createAccounts()
        let email = EmulatorBackend.newEmail(prefix: "signup.teacher")
        let password = "Emulator-\(Int.random(in: 100_000...999_999))"
        launchApp()
        openSignUpForm()
        fillSignUp(email: email, password: password, confirmation: password, agreeToTerms: true)
        submitSignUp()

        // T-05: the profile comes next, not the ID step.
        XCTAssertTrue(nameField.waitForExistence(timeout: 60), "signing up did not reach the profile step")
        XCTAssertFalse(app.buttons["teacher_subjects_continue"].exists, "sign-up showed the subjects step")
        type("Signup Teacher", into: nameField, "the profile's name field")
        type("0521234567", into: phoneField, "the profile's phone field")
        dismissKeyboard()
        XCTAssertTrue(tapWhenHittable(profileContinue, "the profile's Continue"), "the profile's Continue was never tappable")
        // No payout method picked: the app asks, and the test continues anyway.
        XCTAssertTrue(tapWhenHittable(dialogButton, "Continue anyway", timeout: 15), "the missing-payout question did not appear")
        XCTAssertTrue(waitForDashboard(timeout: 90), "finishing the profile did not reach the dashboard")

        let users = try await backend.users(withEmail: email)
        XCTAssertEqual(users.count, 1, "signing up made \(users.count) Auth users")
        let user = try XCTUnwrap(users.first)
        XCTAssertEqual(user.providers, ["password"])
        let profile = try await backend.strings("users/\(user.uid)") ?? [:]
        XCTAssertEqual(profile["role"], "teacher")
        XCTAssertEqual(profile["fullName"], "Signup Teacher")
        XCTAssertEqual(profile["phoneNumber"], "0521234567")
    }

    /// IOS-T-07: the profile's Continue stays off until there is a name and
    /// a valid phone, which a teacher must give.
    @MainActor
    func testProfileNeedsANameAndAValidPhone() async throws {
        try await createAccounts()
        let password = "Emulator-\(Int.random(in: 100_000...999_999))"
        launchApp()
        openSignUpForm()
        fillSignUp(email: EmulatorBackend.newEmail(prefix: "signup.profile"), password: password,
                   confirmation: password, agreeToTerms: true)
        submitSignUp()
        XCTAssertTrue(nameField.waitForExistence(timeout: 60), "signing up did not reach the profile step")

        XCTAssertFalse(profileContinue.isEnabled, "Continue was on with nothing filled in")
        type("Profile Teacher", into: nameField, "the profile's name field")
        dismissKeyboard()
        XCTAssertFalse(profileContinue.isEnabled, "Continue was on without a phone")
        type("123", into: phoneField, "the profile's phone field")
        dismissKeyboard()
        XCTAssertFalse(profileContinue.isEnabled, "Continue was on with the phone 123")
        clear(phoneField)
        type("0521234567", into: phoneField, "the profile's phone field")
        dismissKeyboard()
        XCTAssertTrue(profileContinue.isEnabled, "Continue stayed off with a name and a valid phone")
        clear(nameField)
        dismissKeyboard()
        XCTAssertFalse(profileContinue.isEnabled, "Continue was on without a name")
    }

    /// IOS-T-06: subjects. A teacher with a profile but no subjects is sent
    /// to them; Continue needs a subject, and the ones picked are saved.
    @MainActor
    func testSubjectsAreRequiredAndSaved() async throws {
        try await createAccounts()
        let teacher = try await backend.createAccount(prefix: "signup.subjects")
        try await backend.merge("users/\(teacher.uid)", [
            "role": "teacher", "fullName": "Subjects Teacher", "phoneNumber": "0521234567",
        ])
        launchApp()
        openLoginForm()
        submitLogin(email: teacher.email, password: teacher.password)

        let continueButton = app.buttons["teacher_subjects_continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 60), "a teacher without subjects was not sent to them")
        scrollToHittable(continueButton)
        XCTAssertFalse(continueButton.isEnabled, "Continue was on with no subject")

        let area = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'teacher_subject_area_'")).firstMatch
        scrollUpToHittable(area)
        XCTAssertTrue(tapWhenHittable(area, "a subject area"), "no subject area to pick")
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'subject_chip_'"))
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 10), "picking an area showed no subjects")
        for index in 0..<2 {
            let chip = chips.element(boundBy: index)
            scrollToHittable(chip)
            XCTAssertTrue(tapWhenHittable(chip, "subject \(index + 1)"), "subject \(index + 1) was never tappable")
        }
        scrollToHittable(continueButton)
        XCTAssertTrue(continueButton.isEnabled, "Continue stayed off with two subjects")
        continueButton.tap()
        XCTAssertTrue(waitForDashboard(timeout: 90), "saving the subjects did not reach the dashboard")

        let saved = try await subjectCount(of: teacher.uid)
        XCTAssertEqual(saved, 2, "subjectSelections holds \(saved) subjects")
    }

    /// IOS-T-10: killed on the profile step, the app opens on it again.
    @MainActor
    func testKilledOnTheProfileStepResumesThere() async throws {
        try await createAccounts()
        let email = EmulatorBackend.newEmail(prefix: "signup.resume")
        let password = "Emulator-\(Int.random(in: 100_000...999_999))"
        launchApp()
        openSignUpForm()
        fillSignUp(email: email, password: password, confirmation: password, agreeToTerms: true)
        submitSignUp()
        XCTAssertTrue(nameField.waitForExistence(timeout: 60), "signing up did not reach the profile step")

        app.terminate()
        launchApp(signedOut: false)
        let resumed = waitForAny([nameField, app.buttons["welcome_log_in"], app.switches["availability_toggle"]],
                                 timeout: 60)
        XCTAssertEqual(resumed?.identifier, "complete_profile_full_name",
                       "after a relaunch the app opened on \(resumed?.identifier ?? "nothing") instead of the profile")
        let users = try await backend.users(withEmail: email)
        XCTAssertEqual(users.count, 1, "the new account is gone")
    }

    /// IOS-T-11: an address that already has an account is refused, and no
    /// second account appears.
    @MainActor
    func testAnAddressInUseIsRefused() async throws {
        try await createAccounts()
        launchApp()
        openSignUpForm()
        let password = "Emulator-\(Int.random(in: 100_000...999_999))"
        fillSignUp(email: appTeacher.email, password: password, confirmation: password, agreeToTerms: true)
        submitSignUp()

        XCTAssertTrue(dialogButton.waitForExistence(timeout: 30), "signing up with an address in use showed no error")
        let screen = app.debugDescription
        attach("refusal", screen)
        XCTAssertTrue(inUseMessages.contains { screen.contains($0) },
                      "the error does not say the address is in use")
        dialogButton.tap()
        XCTAssertTrue(app.textFields["sign_up_email"].exists, "the sign-up form is gone")
        XCTAssertFalse(nameField.exists, "an address in use went on to the profile")
        let users = try await backend.users(withEmail: appTeacher.email)
        XCTAssertEqual(users.count, 1, "the address has \(users.count) accounts")
        let canSignIn = try await backend.canSignIn(appTeacher)
        XCTAssertTrue(canSignIn, "the existing account no longer signs in with its own password")
    }

    /// IOS-T-12: each invalid form is refused on Continue with a message, and
    /// none of them creates an account.
    @MainActor
    func testInvalidSignUpsAreRefused() async throws {
        try await createAccounts()
        let email = EmulatorBackend.newEmail(prefix: "signup.invalid")
        launchApp()
        openSignUpForm()

        let cases: [(String, String, String, String, Bool)] = [
            ("a bad address", "not-an-address", "Emulator-123456", "Emulator-123456", true),
            ("a short password", email, "12345", "12345", true),
            ("a mismatched confirmation", email, "Emulator-123456", "Emulator-654321", true),
            ("unaccepted terms", email, "Emulator-123456", "Emulator-123456", false),
        ]
        for (described, address, password, confirmation, agree) in cases {
            fillSignUp(email: address, password: password, confirmation: confirmation, agreeToTerms: agree)
            submitSignUp()
            XCTAssertTrue(dialogButton.waitForExistence(timeout: 15), "\(described): no error")
            attach(described, app.debugDescription)
            dialogButton.tap()
            XCTAssertTrue(waitForDisappearance(dialogButton, timeout: 10), "\(described): the error stayed")
            XCTAssertFalse(nameField.exists, "\(described): went on to the profile")
        }
        let users = try await backend.users(withEmail: email)
        XCTAssertTrue(users.isEmpty, "an invalid sign-up created an account")
    }

    /// IOS-T-13: a student account is turned away with the notice about the
    /// student app, signed out, and left a student.
    @MainActor
    func testAStudentAccountIsTurnedAway() async throws {
        try await createAccounts()
        launchApp()
        openLoginForm()
        submitLogin(email: student.email, password: student.password)

        XCTAssertTrue(dialogButton.waitForExistence(timeout: 60), "a student account got no notice")
        attach("notice", app.debugDescription)
        XCTAssertFalse(app.switches["availability_toggle"].exists, "a student account reached the dashboard")
        dialogButton.tap()
        XCTAssertTrue(app.buttons["welcome_log_in"].waitForExistence(timeout: 15),
                      "the notice did not leave the app on the welcome screen")
        let profile = try await backend.strings("users/\(student.uid)") ?? [:]
        XCTAssertEqual(profile["role"], "student", "signing in to Pro Teacher changed the student's role")

        // Signed out for real: a relaunch keeping the session opens signed out.
        app.terminate()
        launchApp(signedOut: false)
        let landed = waitForAny([app.buttons["welcome_log_in"], app.switches["availability_toggle"]], timeout: 60)
        XCTAssertEqual(landed?.identifier, "welcome_log_in", "the student account stayed signed in")
    }

    // MARK: - Steps

    /// From the welcome screen to the sign-up form.
    @MainActor
    private func openSignUpForm() {
        let emailField = app.textFields["sign_up_email"]
        for _ in 0..<5 where !emailField.exists {
            XCTAssertTrue(tapWhenHittable(app.buttons["welcome_sign_up"], "the welcome screen's Sign up"),
                          "the welcome screen's Sign up never appeared")
            _ = emailField.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(emailField.exists, "the sign-up form did not open")
    }

    /// Fills the form from scratch; `agreeToTerms` leaves the terms box
    /// checked or unchecked whatever it was.
    @MainActor
    private func fillSignUp(email: String, password: String, confirmation: String, agreeToTerms: Bool) {
        let emailField = app.textFields["sign_up_email"]
        clear(emailField)
        type(email, into: emailField, "the sign-up email field")
        for (id, text) in [("sign_up_password", password), ("sign_up_confirm_password", confirmation)] {
            typeSecure(text, into: app.secureTextFields[id], id)
        }
        dismissKeyboard()
        let terms = app.descendants(matching: .any)["sign_up_terms"].firstMatch
        scrollToHittable(terms)
        XCTAssertTrue(terms.waitForExistence(timeout: 10), "no terms box")
        if isChecked(terms) != agreeToTerms {
            XCTAssertTrue(tapWhenHittable(terms, "the terms box"), "the terms box was never tappable")
        }
    }

    /// Replaces a password field's text. Focusing a new-password field makes
    /// iOS offer a strong password in a sheet that swallows the typing, so the
    /// sheet is closed first.
    @MainActor
    private func typeSecure(_ text: String, into field: XCUIElement, _ described: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 20), "no \(described)")
        for _ in 0..<3 {
            XCTAssertTrue(tapWhenHittable(field, described), "\(described) was never tappable")
            // No sheet means the tap left the field focused; after closing
            // one, the field is tapped again to take the focus back.
            if !closeStrongPasswordSheet() { break }
        }
        let existing = (field.value as? String).map { $0 == field.placeholderValue ? 0 : $0.count } ?? 0
        if existing > 0 {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing + 2))
        }
        field.typeText(text)
        _ = closeStrongPasswordSheet(wait: 0.5)
    }

    /// Closes iOS's "Use Strong Password?" sheet if it opens within `wait`.
    @MainActor
    private func closeStrongPasswordSheet(wait: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(wait)
        // Asking a process that is not running retries for seconds per
        // button, so only the running ones are asked.
        let hosts = (systemPromptHosts + [app!]).filter { $0.state != .notRunning }
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
    private func submitSignUp() {
        let button = app.buttons["sign_up_continue"]
        scrollToHittable(button)
        XCTAssertTrue(tapWhenHittable(button, "the sign-up Continue"), "the sign-up Continue was never tappable")
    }

    /// The checkbox reports its state as its value or as selection.
    private func isChecked(_ box: XCUIElement) -> Bool {
        if box.isSelected { return true }
        let value = (box.value as? String)?.lowercased() ?? ""
        return value == "1" || value == "checked" || value == "on" || value == "true"
    }

    private func subjectCount(of uid: String) async throws -> Int {
        let fields = try await backend.fields("users/\(uid)") ?? [:]
        let areas = ((fields["subjectSelections"] as? [String: Any])?["mapValue"] as? [String: Any])?["fields"]
            as? [String: [String: Any]] ?? [:]
        return areas.values.reduce(0) { total, area in
            total + (((area["arrayValue"] as? [String: Any])?["values"] as? [Any])?.count ?? 0)
        }
    }

    @MainActor
    private func scrollToHittable(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }

    @MainActor
    private func scrollUpToHittable(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeDown()
        }
    }
}
