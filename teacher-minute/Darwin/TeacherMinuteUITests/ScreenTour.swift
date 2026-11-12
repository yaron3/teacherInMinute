//
//  ScreenTour.swift
//  TeacherMinuteUITests
//
//  The main screens of each app, visited in turn against the local Firebase
//  emulators, with a check run on each: the student app as a guest, Pro
//  Teacher as a new teacher. Used by AppearanceUITests (IOS-G-03) and
//  LayoutUITests (IOS-E-06).
//

import XCTest

extension ProTeacherEmulatorTestCase {

    /// Instant Teacher as a guest: intro, home (photo and text), the menu,
    /// Activity, Profile, Settings and Help.
    @MainActor
    func tourTheStudentApp(extraArguments: [String] = [], _ check: @escaping (String) -> Void) async throws {
        guard await backend.isRunning() else { throw XCTSkip("Firebase emulators not running") }
        app = XCUIApplication(bundleIdentifier: "com.yaronj.student")
        app.launchArguments = [
            "-firebaseEmulatorHost", EmulatorBackend.host, "-firebaseEmulatorSignOut", "YES",
            "-tutorial.student.hidden", "YES",
        ] + extraArguments
        app.launch()
        let start = app.buttons["student_intro_start"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "the intro did not open")
        check("intro")
        let deadline = Date().addingTimeInterval(40)
        while start.exists && Date() < deadline {
            _ = tapIfPresent(start)
            pause(seconds: 3)
        }
        let textTab = app.buttons["question_home_mode_text"]
        XCTAssertTrue(textTab.waitForExistence(timeout: 60), "Start did not reach home")
        pause(seconds: 2)
        check("home-photo")
        XCTAssertTrue(tapWhenHittable(textTab, "the Text tab"), "no Text tab")
        pause(seconds: 1)
        check("home-text")

        for item in ["activity", "profile", "settings", "help"] {
            XCTAssertTrue(tapWhenHittable(app.buttons["side_menu_button"], "the menu"), "no menu button")
            if item == "activity" {
                XCTAssertTrue(app.buttons["side_menu_item_activity"].waitForExistence(timeout: 10), "the menu did not open")
                pause(seconds: 1)
                check("menu")
            }
            XCTAssertTrue(tapWhenHittable(app.buttons["side_menu_item_\(item)"], item), "no \(item) in the menu")
            pause(seconds: 2)
            check(item)
            _ = tapIfPresent(app.buttons["brand_sheet_close"])
        }
    }

    /// Pro Teacher signed in as a new teacher: welcome, login, the dashboard,
    /// Lessons, Earnings, Profile and Settings.
    @MainActor
    func tourTheTeacherApp(extraArguments: [String] = [], _ check: @escaping (String) -> Void) async throws {
        try await createAccounts()
        launchApp(extraArguments: extraArguments)
        // On a small screen the welcome's Sign up and Log in can sit below
        // the fold: scrolled to, and said so.
        let logIn = app.buttons["welcome_log_in"]
        _ = logIn.waitForExistence(timeout: 30)
        check("welcome")
        var swipes = 0
        while !(logIn.exists && logIn.isHittable) && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        if swipes > 0 {
            attach("welcome", logIn.isHittable
                ? "Log in was below the fold: \(swipes) swipe(s) up to reach it"
                : "Log in could not be reached by scrolling")
        }
        XCTAssertTrue(logIn.exists && logIn.isHittable, "the welcome screen's Log in cannot be reached")
        openLoginForm()
        check("login")
        submitLogin(email: appTeacher.email, password: appTeacher.password)
        XCTAssertTrue(waitForDashboard(timeout: 90), "signing in did not reach the dashboard")
        let sheet = app.sheets["Save Password?"]
        if sheet.waitForExistence(timeout: 15) { _ = tapIfPresent(sheet.buttons["Not Now"]) }
        pause(seconds: 2)
        check("dashboard")
        for tab in ["lessons", "earnings", "profile", "settings"] {
            XCTAssertTrue(tapWhenHittable(app.buttons["tab_item_\(tab)"], tab), "no \(tab) tab")
            pause(seconds: 2)
            check(tab)
        }
    }
}
