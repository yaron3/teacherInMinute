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
//   IOS-G-06  editing the profile saves a new name and phone, and shows them
//   IOS-G-08  Contact Us takes images from the photo library (IT-32): each
//             shows on the form, one can be taken off again, and the preview
//             lists them. It stops at the preview: sending mails the support
//             team for real, even from the emulators, so that half stays a
//             manual check (backend: contactSupport.test.ts and
//             contactRequests.rules.emulator.test.ts)
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

    /// IOS-G-06: a new name and phone are saved to the profile and shown.
    @MainActor
    func testEditingTheProfileSavesNameAndPhone() async throws {
        try await signInAsNewTeacher()
        settleAfterSignIn()
        try require(tapWhenHittable(app.buttons["tab_item_profile"], "the Profile tab"), "no Profile tab")
        try require(tapWhenHittable(app.buttons["profile_edit_button"], "Edit profile"), "no Edit on the profile")

        let name = "Renamed Teacher \(Int.random(in: 100...999))"
        let nameField = app.textFields["profile_field_name"]
        try require(nameField.waitForExistence(timeout: 15), "the profile editor has no name field")
        clear(nameField)
        type(name, into: nameField, "the name field")
        let phoneField = app.textFields["profile_field_phone"]
        clear(phoneField)
        type("0529876543", into: phoneField, "the phone field")
        dismissKeyboard()
        let save = app.buttons["profile_save_button"]
        for _ in 0..<4 where !(save.exists && save.isHittable) { app.swipeUp() }
        try require(tapWhenHittable(save, "Save"), "no Save in the profile editor")
        try require(waitForDisappearance(save, timeout: 20), "saving did not close the editor")

        var saved: [String: String] = [:]
        let deadline = Date().addingTimeInterval(20)
        repeat {
            saved = try await backend.strings("users/\(appTeacher.uid)") ?? [:]
            if saved["fullName"] != name { pause(seconds: 0.5) }
        } while saved["fullName"] != name && Date() < deadline
        XCTAssertEqual(saved["fullName"], name, "the new name was not saved")
        XCTAssertEqual(saved["phoneNumber"], "0529876543", "the new phone was not saved")
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10), "the profile does not show the new name")
    }

    /// IOS-G-08, up to the preview: images attach, come off, and are listed.
    @MainActor
    func testContactUsAttachesImagesAndListsThemInThePreview() async throws {
        try await signInAsNewTeacher()
        settleAfterSignIn()
        try openSettingsRow("about")
        try require(tapWhenHittable(app.buttons["settings_row_contactUs"], "Contact Us"), "no Contact Us row in About")

        try attachImageFromLibrary()
        try require(app.buttons["contact_support_remove_attachment_0"].waitForExistence(timeout: 15),
                    "the first image did not show on the form")
        try attachImageFromLibrary()
        try require(app.buttons["contact_support_remove_attachment_1"].waitForExistence(timeout: 15),
                    "the second image did not show on the form")
        try require(app.staticTexts["2/3"].exists, "the form does not count two images")

        try require(tapWhenHittable(app.buttons["contact_support_remove_attachment_1"], "remove image"),
                    "no way to take an image off")
        try require(waitForDisappearance(app.buttons["contact_support_remove_attachment_1"], timeout: 10),
                    "the image stayed on the form")
        try require(app.staticTexts["1/3"].waitForExistence(timeout: 5), "the form does not count one image")
        keepScreenshot("contact-us-form")

        let title = app.textFields.firstMatch
        try require(title.waitForExistence(timeout: 10), "no title field on Contact Us")
        type("Board froze", into: title, "the title field")
        let description = app.textViews.firstMatch
        try require(tapWhenHittable(description, "the description"), "no description on Contact Us")
        description.typeText("The board froze mid-lesson; a screenshot is attached.")
        dismissKeyboard()

        let preview = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["Preview and Submit", "תצוגה מקדימה ושליחה"]
        )).firstMatch
        for _ in 0..<4 where !(preview.exists && preview.isHittable) { app.swipeUp() }
        try require(tapWhenHittable(preview, "Preview and Submit"), "no Preview and Submit")

        let close = app.buttons["brand_sheet_close"]
        try require(close.waitForExistence(timeout: 20), "the preview did not open")
        let attachmentsTitle = app.staticTexts.matching(NSPredicate(
            format: "label IN %@", ["Attachments", "קבצים מצורפים"]
        ))
        // Once in the data rows (with its count) and once over the thumbnails.
        try require(attachmentsTitle.firstMatch.waitForExistence(timeout: 10), "the preview does not list the attachments")
        keepScreenshot("contact-us-preview")

        // Never Send: that would email the support team for real.
        try require(tapWhenHittable(close, "close the preview"), "no way to close the preview")
        try require(waitForDisappearance(close, timeout: 10), "the preview did not close")
        try require(app.buttons["contact_support_remove_attachment_0"].exists,
                    "cancelling the preview dropped the image")
    }

    // MARK: - Steps

    /// Kept even when the test passes, for whoever reviews the run.
    @MainActor
    private func keepScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The add tile, "Choose from Library", and the first photo in the
    /// system picker, which closes itself on a single pick.
    @MainActor
    private func attachImageFromLibrary() throws {
        let add = app.buttons["contact_support_add_attachment"]
        for _ in 0..<4 where !(add.exists && add.isHittable) { app.swipeUp() }
        try require(tapWhenHittable(add, "add image"), "no add-image tile on Contact Us")
        let library = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["Choose from Library", "בחר מהספרייה"]
        )).firstMatch
        try require(tapWhenHittable(library, "Choose from Library"), "no Choose from Library in the dialog")
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
        try require(photo.waitForExistence(timeout: 20), "the photo picker shows no photos")
        // The picker slides up after its photos exist; tapped once it settles.
        if waitForHittable(photo, timeout: 10) {
            photo.tap()
        } else {
            photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        try require(waitForDisappearance(photo, timeout: 15), "picking a photo did not close the picker")
    }

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
