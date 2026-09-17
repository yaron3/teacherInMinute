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
}
