//
//  SessionShots.swift
//  TeacherMinuteUITests
//
//  Screenshots of a live lesson's stages — the start, the middle, the end —
//  for scripts/ui-tests/run_session_screenshots.sh. Off unless the run sets
//  SESSION_SHOTS=1 (TEST_RUNNER_SESSION_SHOTS through xcodebuild), so the
//  lesson tests behave exactly as before in every other run.
//
//  Each shot is a keep-always attachment named `shot-<name>`; the script
//  exports them from the .xcresult.
//

import XCTest

extension XCTestCase {

    var sessionShotsEnabled: Bool {
        ProcessInfo.processInfo.environment["SESSION_SHOTS"] == "1"
    }

    /// A picture of the whole screen, kept in the result bundle.
    @MainActor
    func sessionShot(_ name: String) {
        guard sessionShotsEnabled else { return }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "shot-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Sends one chat message, so the middle of the lesson shows an exchange.
    /// Best effort: a lesson whose message field cannot be reached is still a
    /// lesson, and the test goes on.
    @MainActor
    func sendSessionMessage(_ app: XCUIApplication, _ text: String) {
        guard sessionShotsEnabled else { return }
        let chat = app.buttons["session_tab_chat"]
        if chat.exists && chat.isHittable { chat.tap() }
        let field = app.textFields["chat_message_field"]
        guard field.waitForExistence(timeout: 10), field.isHittable else { return }
        field.tap()
        field.typeText(text)
        let send = app.buttons["chat_send_button"]
        if send.waitForExistence(timeout: 5), send.isHittable { send.tap() }
        // Close the keyboard, so the shot shows the thread: a tap at the very
        // top (the lesson's own tests do the same), else the keyboard's Done.
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        for key in ["Done", "done"] where app.keyboards.buttons[key].exists {
            app.keyboards.buttons[key].tap()
        }
    }
}
