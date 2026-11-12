//
//  ChatSessionUITests.swift
//  TeacherMinuteUITests
//
//  The lesson screen reads its thread straight from the session view model.
//  This checks that a sent message reaches the screen that way.
//
//  Runs on the same mock lesson as SessionTypeSwitchUITests, opened with
//  `-uiTestSessionTypeSwitch`, so no question is ever sent to a teacher.
//

import XCTest

final class ChatSessionUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments.append("-uiTestSessionTypeSwitch")
        app.launch()

        XCTAssertTrue(
            app.buttons["session_type_change"].waitForExistence(timeout: 30),
            "the lesson screen did not open"
        )
    }

    @MainActor
    func testSentMessageAppearsInTheThread() throws {
        let text = "UI test message \(Int(Date().timeIntervalSince1970))"

        let field = app.textFields["chat_message_field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no message field")
        if !field.isHittable {
            app.swipeUp()
        }
        field.tap()
        field.typeText(text)

        let send = app.buttons["chat_send_button"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "no send button")
        send.tap()

        let sent = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "the sent message never appeared in the thread")

        let fieldValue = field.value as? String ?? ""
        XCTAssertFalse(fieldValue.contains(text), "the message field was not cleared after sending")
    }

    /// IOS-E-05: a long message mixing Hebrew, English and emoji goes into
    /// the thread whole and wraps inside the screen.
    @MainActor
    func testALongMixedMessageFitsTheScreen() throws {
        let token = "E05-\(Int(Date().timeIntervalSince1970))"
        let text = "שלום! I'm stuck on שאלה 7 🤔📐 — \(token) — "
            + String(repeating: "x² + 3x − 4 = 0 אבל למה? why does it not factor? 😅 ", count: 4)

        let field = app.textFields["chat_message_field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no message field")
        if !field.isHittable { app.swipeUp() }
        field.tap()
        field.typeText(text)
        app.buttons["chat_send_button"].tap()

        let sent = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", token)).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "the long mixed message never appeared")
        XCTAssertTrue(sent.label.contains("😅") && sent.label.contains("שאלה"), "the message lost its Hebrew or emoji: \(sent.label)")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(sent.frame.minX, window.minX - 1, "the message runs off the left edge: \(sent.frame)")
        XCTAssertLessThanOrEqual(sent.frame.maxX, window.maxX + 1, "the message runs off the right edge: \(sent.frame)")
        XCTAssertGreaterThan(sent.frame.height, 40, "the long message did not wrap: \(sent.frame)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "long mixed message"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
