//
//  LessonChromeUITests.swift
//  TeacherMinuteUITests
//
//  The lesson screen's frame on whatever iPhone runs it — the plan's testers
//  found it overflowing on a 390pt iPhone 12. On the mock lesson
//  (`-uiTestSessionTypeSwitch`, so no question is ever sent), with
//  everything the strip can show at once:
//
//   - an audio lesson, so the microphone badges ride over the people,
//   - the mascot pointing at the board, with its speech bubble,
//   - the media pill open, and
//   - a long message of words too long for a line,
//
//  every part of the top bar and the bottom strip lies inside the screen
//  (Bug-018, Bug-019), the message field is clear of the strip (Bug-017),
//  and the message's text lies inside the screen (Bug-015). Each state is kept
//  as a screenshot.
//

import XCTest

final class LessonChromeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments.append("-uiTestSessionTypeSwitch")
        app.launch()
        XCTAssertTrue(app.buttons["session_type_change"].waitForExistence(timeout: 30), "the lesson screen did not open")
    }

    @MainActor
    func testTheLessonFrameFitsTheScreen() throws {
        // Audio, as the other side asks and this side accepts.
        tap("uitest_peer_switch_audio")
        let confirm = app.buttons["dialog_confirm_button"]
        if confirm.waitForExistence(timeout: 10) { confirm.tap() }
        sleep(1)
        keep("audio")
        check("audio")

        // The mascot points at the board: its bubble joins the strip.
        tap("uitest_peer_board")
        XCTAssertTrue(app.descendants(matching: .any)["session_mascot_message"].waitForExistence(timeout: 10),
                      "the mascot said nothing about the board")
        keep("audio, mascot")
        check("audio, mascot")

        // A message of words too long for a line.
        let word = String(repeating: "m", count: 60)
        let text = "Start\(word) \(String(repeating: "dh", count: 40))End"
        let field = app.textFields["chat_message_field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no message field")
        field.tap()
        field.typeText(text)
        app.buttons["chat_send_button"].tap()
        let sent = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Start'")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "the long message never appeared")
        dismissKeyboard()
        keep("long message")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(CGRect(x: sent.frame.minX, y: window.midY, width: sent.frame.width, height: 1)),
                      "the long message runs past the screen's edge: \(sent.frame) in \(window)")

        // The media pill open, as the testers had it.
        if app.buttons["session_media_options"].exists {
            app.buttons["session_media_options"].tap()
            sleep(1)
        }
        keep("audio, mascot, pill open")
        check("audio, mascot, pill open")
    }

    // MARK: - Checks

    @MainActor
    private func check(_ state: String) {
        let window = app.windows.firstMatch.frame
        let bounds = window.insetBy(dx: -1, dy: -1)
        for id in ["session_end_button", "session_tab_chat", "session_tab_board", "session_type_change",
                   "session_timer", "session_mascot_message", "session_media_options",
                   "session_mic_toggle", "session_camera_toggle"] {
            let element = app.descendants(matching: .any)[id].firstMatch
            guard element.exists else { continue }
            XCTAssertTrue(bounds.contains(element.frame), "[\(state)] \(id) is cut off: \(element.frame) in \(window)")
        }
        // The field is clear of everything the strip draws above its own top:
        // the people's badges stand on a line 24pt over the portraits, and the
        // strip now keeps that room. The media control's label is the
        // strip's lowest-standing row, so the field must end well above it.
        let field = app.textFields["chat_message_field"]
        let media = app.buttons["session_type_change"]
        if field.exists, field.isHittable, media.exists {
            XCTAssertLessThan(field.frame.maxY + 60, media.frame.minY,
                              "[\(state)] the message field sits on the strip: field \(field.frame), media \(media.frame)")
        }
    }

    @MainActor
    private func keep(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no \(id)")
        button.tap()
    }

    @MainActor
    private func dismissKeyboard() {
        if app.keyboards.count > 0 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
    }
}
