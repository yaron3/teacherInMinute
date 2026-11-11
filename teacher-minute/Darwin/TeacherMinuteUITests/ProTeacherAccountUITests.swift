//
//  ProTeacherAccountUITests.swift
//  TeacherMinuteUITests
//
//  Pro Teacher's account life cycle, against the real backend on the local
//  Firebase emulators. QA test plan:
//
//   IOS-A-03  a wrong password, three times: an error each time, then the
//             right one still works
//   IOS-A-06  logging out while online takes the teacher offline at once
//   IOS-A-07  a relaunch keeps the teacher signed in
//   IOS-A-09  deleting the account while online: offline, gone, never invited
//
//  Setup and running are as for ProTeacherAcceptRaceUITests.
//

import XCTest

final class ProTeacherAccountUITests: ProTeacherEmulatorTestCase {

    /// "Incorrect email or password.", in either language.
    private let wrongPasswordMessages = ["Incorrect email or password.", "כתובת המייל או הסיסמה שגויים."]

    /// IOS-A-03: three wrong passwords, each refused with a dialog over the
    /// form; then the right one signs in.
    @MainActor
    func testWrongPasswordIsRefusedEachTime() async throws {
        try await createAccounts()
        launchApp()
        openLoginForm()

        for attempt in 1...3 {
            submitLogin(email: appTeacher.email, password: "Wrong-\(attempt)-\(appTeacher.password)")
            XCTAssertTrue(dialogButton.waitForExistence(timeout: 30), "attempt \(attempt): no error")
            let text = app.debugDescription
            attach("refusal \(attempt)", text)
            XCTAssertTrue(wrongPasswordMessages.contains { text.contains($0) },
                          "attempt \(attempt): the error does not say the email or password is wrong")
            dialogButton.tap()
            XCTAssertTrue(waitForDisappearance(dialogButton, timeout: 10), "attempt \(attempt): the error stayed")
            XCTAssertTrue(app.textFields["email_input"].exists, "attempt \(attempt): the login form is gone")
            XCTAssertFalse(app.switches["availability_toggle"].exists, "attempt \(attempt): a wrong password signed in")
        }

        submitLogin(email: appTeacher.email, password: appTeacher.password)
        XCTAssertTrue(waitForDashboard(timeout: 90), "the right password did not sign in after three wrong ones")
    }

    /// IOS-A-06: logging out while online takes the teacher offline before
    /// the app leaves the dashboard.
    @MainActor
    func testLoggingOutWhileOnlineGoesOffline() async throws {
        try await signInAsNewTeacher()
        let online = try await waitForPresence(online: true)
        XCTAssertTrue(online, "the teacher never went online")

        logOut()

        let offline = try await waitForPresence(online: false, timeout: 10)
        let status = try await backend.value("teachers/\(appTeacher.uid)/status") as? String
        let projected = try await backend.exists("onlineTeachers/\(appTeacher.uid)")
        XCTAssertTrue(offline, "still online after logging out: status=\(status ?? "-") onlineTeachers=\(projected)")
    }

    /// IOS-A-07: the app keeps its session across a relaunch.
    @MainActor
    func testRelaunchStaysSignedIn() async throws {
        try await signInAsNewTeacher()
        app.terminate()

        launchApp(signedOut: false)
        XCTAssertTrue(waitForDashboard(timeout: 60), "a relaunch did not return to the dashboard")
        XCTAssertFalse(app.buttons["welcome_log_in"].exists, "a relaunch showed the welcome screen")
    }

    /// IOS-A-09: deleting the account while online takes the teacher out of
    /// dispatch for good.
    @MainActor
    func testDeletingTheAccountWhileOnline() async throws {
        try await signInAsNewTeacher()
        try await prepareRealDispatch()
        let online = try await waitForPresence(online: true)
        XCTAssertTrue(online, "the teacher never went online")
        // Records only the server's deletion removes: the app alone used to
        // delete just the users document and the login.
        try await backend.merge("teachers/\(appTeacher.uid)", ["bio": "Deleted with the account"])
        try await backend.merge("users/\(appTeacher.uid)/inbox/welcome", ["title": "Welcome"])

        deleteAccount()

        let canSignIn = try await backend.canSignIn(appTeacher)
        XCTAssertFalse(canSignIn, "the deleted account can still sign in")
        let profile = try await backend.strings("users/\(appTeacher.uid)")
        XCTAssertNil(profile, "the deleted teacher's profile is still there")
        let teacherRecord = try await backend.strings("teachers/\(appTeacher.uid)")
        XCTAssertNil(teacherRecord, "the deleted teacher's record is still there")
        let inbox = try await backend.strings("users/\(appTeacher.uid)/inbox/welcome")
        XCTAssertNil(inbox, "the deleted teacher's inbox is still there")

        let qid = try await ask()
        let otherInvited = try await waitForInvite(of: otherTeacher, to: qid)
        XCTAssertTrue(otherInvited, "dispatch did not run: the other teacher was not invited either")
        pause(seconds: 5)
        let invited = try await backend.exists("teacherInvites/\(appTeacher.uid)/\(qid)")
        XCTAssertFalse(invited, "the deleted teacher was invited")

        let offline = try await waitForPresence(online: false, timeout: 15)
        let status = try await backend.value("teachers/\(appTeacher.uid)/status") as? String
        let projected = try await backend.exists("onlineTeachers/\(appTeacher.uid)")
        XCTAssertTrue(offline, "still online after deleting the account: status=\(status ?? "-") onlineTeachers=\(projected)")
    }

    // MARK: - Steps

    /// Waits until the app's teacher is online (status online and listed in
    /// onlineTeachers) or offline (neither).
    @MainActor
    private func waitForPresence(online: Bool, timeout: TimeInterval = 30) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let status = try await backend.value("teachers/\(appTeacher.uid)/status") as? String
            let projected = try await backend.exists("onlineTeachers/\(appTeacher.uid)")
            if online ? (status == "online" && projected) : (status != "online" && !projected) { return true }
            pause(seconds: 0.5)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func logOut() {
        openAccountSecurity()
        XCTAssertTrue(tapWhenHittable(app.buttons["settings_row_logOut"], "the Log Out row"),
                      "the Log Out row was never tappable")
        XCTAssertTrue(tapWhenHittable(dialogButton, "the log-out confirmation"),
                      "the log-out confirmation did not appear")
        XCTAssertTrue(app.buttons["welcome_log_in"].waitForExistence(timeout: 30),
                      "logging out did not return to the welcome screen")
    }

    @MainActor
    private func deleteAccount() {
        openAccountSecurity()
        let row = app.buttons["settings_row_deleteAccount"]
        scrollToHittable(row)
        XCTAssertTrue(tapWhenHittable(row, "the Delete Account row"), "the Delete Account row was never tappable")

        // First "this cannot be undone", then the password.
        XCTAssertTrue(tapWhenHittable(dialogButton, "the delete confirmation"),
                      "the delete confirmation did not appear")
        let passwordField = app.secureTextFields["dialog_secure_input"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 20), "deleting did not ask for the password")
        type(appTeacher.password, into: passwordField, "the delete dialog's password field")
        XCTAssertTrue(tapWhenHittable(dialogButton, "the dialog's Delete button"),
                      "the dialog's Delete button was never tappable")

        let welcome = app.buttons["welcome_log_in"]
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline && !welcome.exists {
            if dialogButton.exists && !passwordField.exists {
                return XCTFail("deleting the account failed: \(dialogText())")
            }
            pause()
        }
        XCTAssertTrue(welcome.exists, "deleting the account did not return to the welcome screen")
    }

    @MainActor
    private func openAccountSecurity() {
        // iOS's "Save Password?" sheet can arrive late after logging in, and
        // covers the screen.
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        let settingsTab = app.buttons["tab_item_settings"]
        if settingsTab.waitForExistence(timeout: 5) {
            XCTAssertTrue(tapWhenHittable(settingsTab, "the Settings tab", timeout: 20),
                          "the Settings tab was never tappable")
        } else {
            XCTAssertTrue(tapWhenHittable(app.buttons["side_menu_button"], "the side-menu button"),
                          "the side-menu button was never tappable")
            let item = app.buttons["side_menu_item_settings"]
            _ = item.waitForExistence(timeout: 10)
            scrollToHittable(item)
            attach("menu", app.debugDescription)
            XCTAssertTrue(tapWhenHittable(item, "the menu's Settings row", timeout: 10),
                          "the menu's Settings row was never tappable")
        }
        let accountSecurity = app.buttons["settings_row_accountSecurity"]
        XCTAssertTrue(accountSecurity.waitForExistence(timeout: 15), "Settings did not open")
        scrollToHittable(accountSecurity)
        XCTAssertTrue(tapWhenHittable(accountSecurity, "the Account & Security row", timeout: 10),
                      "the Account & Security row was never tappable")
        if !app.buttons["settings_row_logOut"].waitForExistence(timeout: 15) {
            attach("screen", app.debugDescription)
            XCTFail("Account & Security did not open")
        }
    }

    /// Swipes up until `element` can be tapped, at most a few times.
    @MainActor
    private func scrollToHittable(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }
}
