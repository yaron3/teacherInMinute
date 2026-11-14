//
//  ChatBugFixUITests.swift
//  TeacherMinuteUITests
//
//  Lesson-chat bugs from the Bug list, on the mock lesson
//  (`-uiTestSessionTypeSwitch`), so no question is ever sent to a teacher.
//  The harness's "Message" button stands in for the other side sending a
//  message.
//
//   - IT-25: an unsent draft stays in the input when a message arrives.
//   - IT-22: with a long thread and the keyboard up, the input stays on the
//            screen instead of drifting off it.
//

import XCTest

final class ChatBugFixUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-uiTestSessionTypeSwitch")
        app.launch()
        // The tab toggle, not the bottom bar's media button: the message field
        // takes focus as the lesson opens, and the bar steps aside for the
        // keyboard (IT-22).
        XCTAssertTrue(
            app.buttons["session_tab_board"].waitForExistence(timeout: 30),
            "the lesson screen did not open"
        )
    }

    /// IT-25: the half-typed message is still in the input after the other
    /// side's message lands in the thread.
    @MainActor
    func testUnsentDraftSurvivesAnIncomingMessage() throws {
        let draft = "Half-typed draft"
        let field = messageField()
        field.tap()
        field.typeText(draft)

        tap("uitest_peer_message")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Peer message")).firstMatch
                .waitForExistence(timeout: 10),
            "the incoming message never reached the thread"
        )

        let value = (messageField().value as? String) ?? ""
        XCTAssertTrue(value.contains(draft), "the draft was cleared when the message arrived (value: \"\(value)\")")
        keep("IT-25 draft kept after incoming message")
    }

    /// IT-22: a long thread with the keyboard up. The input has to stay on
    /// screen, not drift past the bottom edge.
    @MainActor
    func testChatInputStaysOnScreenWithALongThreadAndKeyboard() throws {
        for _ in 0..<15 {
            tap("uitest_peer_message")
        }
        let field = messageField()
        field.tap()
        field.typeText("x")

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "the keyboard did not come up (a hardware keyboard may be connected)")
        usleep(800_000)
        let screen = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(
            field.frame.maxY, screen.maxY,
            "the chat input drifted below the screen (field bottom \(field.frame.maxY), screen bottom \(screen.maxY))"
        )
        // The lesson's bottom bar stays behind the keyboard, not on top of it.
        XCTAssertFalse(app.staticTexts["Session Time"].exists, "the lesson's bottom bar rose with the keyboard")
        keep("IT-22 long thread, keyboard up")
    }

    /// IT-23: with the other side's mic and camera off, the status badges sit
    /// on their participant card, not above it over the message area.
    @MainActor
    func testParticipantBadgesStayOnTheirCard() throws {
        tap("uitest_peer_switch_video")
        // The other side's switch asks this side to confirm it.
        let switchButton = app.buttons["Switch"]
        XCTAssertTrue(switchButton.waitForExistence(timeout: 10), "no Switch confirmation")
        switchButton.tap()
        usleep(1_500_000)
        keep("IT-23 video lesson, before peer mic and camera off")
        tap("uitest_peer_media_off")
        usleep(800_000)
        keep("IT-23 video lesson, peer mic and camera off")

        // The peer is "Michael". Their badges must sit above their name, within
        // the width of their own column, not over the bracket or a neighbour.
        let name = app.staticTexts["Michael"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "no participant name to measure against")
        let badges = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'session_badge_'"))
            .allElementsBoundByIndex
            .filter { $0.frame.midX >= name.frame.minX && $0.frame.midX <= name.frame.maxX }
        XCTAssertEqual(badges.count, 2, "the peer's camera and mic badges are not both shown")
        for badge in badges {
            XCTAssertLessThanOrEqual(badge.frame.maxY, name.frame.minY, "a badge sits on or below the name")
            XCTAssertGreaterThanOrEqual(badge.frame.minX, name.frame.minX - 8, "a badge reaches past the card's left edge")
            XCTAssertLessThanOrEqual(badge.frame.maxX, name.frame.maxX + 8, "a badge reaches past the card's right edge")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func messageField() -> XCUIElement {
        let field = app.textFields["chat_message_field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no message field")
        if !field.isHittable {
            app.swipeUp()
        }
        return field
    }

    @MainActor
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no \(id)")
        button.tap()
    }

    @MainActor
    private func keep(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
