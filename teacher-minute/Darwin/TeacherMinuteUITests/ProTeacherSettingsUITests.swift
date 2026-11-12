//
//  ProTeacherSettingsUITests.swift
//  TeacherMinuteUITests
//
//  Settings a teacher uses, against the local Firebase emulators. QA test plan:
//
//   IOS-G-01  Settings → Language → Hebrew: the layout runs right to left;
//             → English: left to right again. The copy follows Remote Config,
//             which the emulators cannot serve, so it stays a manual check
//   IOS-G-05  a message in the inbox shows in Messages, and opening it marks
//             it read (readTimestamp)
//   IOS-G-10  About → Terms and About → Privacy Policy each open a page that
//             loads
//
//  The look of the right-to-left layout stays a manual check; this checks only
//  that it flips. Start the emulators as for ProTeacherAcceptRaceUITests.
//

import XCTest

final class ProTeacherSettingsUITests: ProTeacherEmulatorTestCase {

    /// IOS-G-05: an unread message is listed, then marked read.
    @MainActor
    func testAnInboxMessageIsShownAndMarkedRead() async throws {
        try await createAccounts()
        let title = "Emulator notice \(Int.random(in: 1000...9999))"
        try await backend.merge("users/\(appTeacher.uid)/incomingMessages/emulator-notice", [
            "title": title,
            "text": "Your documents were approved.",
            "createdAt": Date(),
        ])
        launchApp()
        openLoginForm()
        submitLogin(email: appTeacher.email, password: appTeacher.password)
        try require(waitForDashboard(timeout: 90), "signing in did not reach the teacher dashboard")
        settleAfterSignIn()

        // A tap while the dashboard is still settling can miss; tap again
        // until Messages is open.
        let message = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        for _ in 0..<4 where !message.exists {
            try require(tapWhenHittable(app.buttons["messages_button"], "Messages"), "no Messages button on the dashboard")
            _ = message.waitForExistence(timeout: 8)
        }
        try require(message.exists, "the message is not in Messages")

        var read = false
        let deadline = Date().addingTimeInterval(20)
        repeat {
            read = try await backend.fields("users/\(appTeacher.uid)/incomingMessages/emulator-notice")?["readTimestamp"] != nil
            if !read { pause(seconds: 0.5) }
        } while !read && Date() < deadline
        XCTAssertTrue(read, "opening Messages did not mark the message read")
    }

    /// IOS-G-01: Hebrew and back, the layout flipping each way.
    @MainActor
    func testSwitchingLanguageFlipsTheAppAndBack() async throws {
        try await signInAsNewTeacher()
        settleAfterSignIn()
        try openSettingsRow("language")

        // The tab bar may be hidden on the Language page: checked back on Settings.
        try require(tapWhenHittable(app.buttons["language_row_hebrew"], "עברית"), "no Hebrew in Language")
        leaveLanguagePage()
        try expectLanguage(hebrew: true)

        try openSettingsRow("language")
        try require(tapWhenHittable(app.buttons["language_row_english"], "English"), "no English in Language")
        leaveLanguagePage()
        try expectLanguage(hebrew: false)
    }

    /// IOS-G-10: Terms and Privacy Policy each open a page that loads.
    @MainActor
    func testAboutOpensTheTermsAndPrivacyPages() async throws {
        try await signInAsNewTeacher()
        settleAfterSignIn()
        try openSettingsRow("about")

        for row in ["eula", "privacyPolicy"] {
            try require(tapWhenHittable(app.buttons["settings_row_\(row)"], row), "no \(row) row in About")
            let page = app.webViews.firstMatch
            try require(page.waitForExistence(timeout: 20), "\(row) opened no page")
            var loaded = false
            let deadline = Date().addingTimeInterval(30)
            repeat {
                loaded = page.staticTexts.count > 3
                if !loaded { pause(seconds: 1) }
            } while !loaded && Date() < deadline
            try require(loaded, "the \(row) page never loaded any text")
            try require(tapWhenHittable(app.buttons["brand_back_button"], "Back"), "no way back from \(row)")
        }
    }

    // MARK: - Steps

    /// iOS offers to save the password a moment after the dashboard appears,
    /// and the sheet swallows the next tap: waited for and closed first.
    @MainActor
    private func settleAfterSignIn() {
        let sheet = app.sheets["Save Password?"]
        if sheet.waitForExistence(timeout: 20) {
            _ = tapIfPresent(sheet.buttons["Not Now"])
            pause(seconds: 1)
        }
    }

    @MainActor
    private func openSettingsRow(_ id: String) throws {
        let row = app.buttons["settings_row_\(id)"]
        // Tapped again until Settings opens: a tap while a sheet closes misses.
        for _ in 0..<4 where !row.exists {
            try require(tapWhenHittable(app.buttons["tab_item_settings"], "the Settings tab"), "no Settings tab")
            _ = row.waitForExistence(timeout: 5)
        }
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        try require(tapWhenHittable(row, "the \(id) row"), "no \(id) row in Settings")
    }

    /// Back to where the tab bar shows. Picking a language may itself reload
    /// the app at home, leaving no Back to tap.
    @MainActor
    private func leaveLanguagePage() {
        pause(seconds: 2)
        _ = tapIfPresent(app.buttons["brand_back_button"])
    }

    /// The Settings tab's label in the chosen language, and the tab bar's
    /// order: Home first on the left in English, on the right in Hebrew.
    @MainActor
    private func expectLanguage(hebrew: Bool) throws {
        let settingsTitle = hebrew ? "הגדרות" : "Settings"
        let home = app.buttons["tab_item_home"]
        let settings = app.buttons["tab_item_settings"]
        var labelled = false
        var flipped = false
        let deadline = Date().addingTimeInterval(20)
        repeat {
            labelled = settings.label.contains(settingsTitle) || app.staticTexts[settingsTitle].exists
            flipped = home.exists && settings.exists && (hebrew
                ? home.frame.minX > settings.frame.minX
                : home.frame.minX < settings.frame.minX)
            if !flipped { pause(seconds: 0.5) }
        } while !flipped && Date() < deadline
        // The words come from Remote Config, which the emulators cannot serve:
        // the app keeps whatever template it last fetched, so only the layout
        // is checked here and the copy stays a manual check.
        attach("labels in \(hebrew ? "Hebrew" : "English")", "Settings tab reads \(settings.label); matches=\(labelled)")
        guard flipped else {
            attach("screen", app.debugDescription)
            throw Failed("\(hebrew ? "Hebrew" : "English"): labelled=\(labelled) right-to-left order=\(flipped)")
        }
    }

    @MainActor
    private func require(_ condition: Bool, _ message: String) throws {
        guard !condition else { return }
        attach("screen", app?.debugDescription ?? "no app")
        throw Failed(message)
    }

    private struct Failed: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
