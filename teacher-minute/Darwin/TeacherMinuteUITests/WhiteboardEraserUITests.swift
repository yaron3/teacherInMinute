//
//  WhiteboardEraserUITests.swift
//  TeacherMinuteUITests
//
//  The board's eraser (IT-1), on the mock lesson (`-uiTestSessionTypeSwitch`,
//  so no question is ever sent). The harness's "Draw" button stands in for the
//  other side drawing a line straight across the top of the board.
//
//   - A student rubs out their own stroke, and cannot rub out the teacher's.
//   - A teacher rubs out the student's stroke as well as their own.
//   - Rubbing out the last stroke does not tell the eraser's own side that the
//     board was cleared.
//

import XCTest

final class WhiteboardEraserUITests: XCTestCase {

    private var app: XCUIApplication!
    /// The board's frame, taken while it is empty: once strokes are drawn the
    /// identifier also matches them, and a line across the whole board is wider
    /// than the screen.
    private var canvasFrame: CGRect = .zero

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAStudentErasesOnlyTheirOwnStrokes() throws {
        openBoard(asTeacher: false)

        tap("uitest_peer_draw")
        XCTAssertTrue(waitForStrokes(1), "the other side's line never reached the board")
        drawOwnStroke()
        XCTAssertTrue(waitForStrokes(2), "the student's stroke was not drawn")
        keep("student, before erasing")

        tap("whiteboard_tool_eraser")
        sweep(fromY: 0.55, toY: 0.85)
        XCTAssertTrue(waitForStrokes(1), "the student's own stroke was not rubbed out")

        sweep(fromY: 0.03, toY: 0.35)
        sleep(1)
        XCTAssertEqual(strokeCount, 1, "a student rubbed out the teacher's line")
        keep("student, after erasing")
    }

    @MainActor
    func testATeacherErasesBothSidesStrokes() throws {
        openBoard(asTeacher: true)

        tap("uitest_peer_draw")
        XCTAssertTrue(waitForStrokes(1), "the other side's line never reached the board")
        drawOwnStroke()
        XCTAssertTrue(waitForStrokes(2), "the teacher's stroke was not drawn")

        tap("whiteboard_tool_eraser")
        sweep(fromY: 0.03, toY: 0.35)
        XCTAssertTrue(waitForStrokes(1), "the teacher could not rub out the student's line")
        sweep(fromY: 0.55, toY: 0.85)
        XCTAssertTrue(waitForStrokes(0), "the teacher's own stroke was not rubbed out")

        // Rubbing out the last stroke is not the other side clearing the board.
        sleep(1)
        XCTAssertFalse(app.buttons["dialog_confirm_button"].exists, "erasing the last stroke raised the cleared-board dialog")
        keep("teacher, board erased")

        // The pen is back in hand after picking it again.
        tap("whiteboard_tool_pen")
        drawOwnStroke()
        XCTAssertTrue(waitForStrokes(1), "the pen did not draw after the eraser")
    }

    // MARK: - Helpers

    @MainActor
    private func openBoard(asTeacher: Bool) {
        app = XCUIApplication()
        app.launchArguments.append("-uiTestSessionTypeSwitch")
        if asTeacher { app.launchArguments.append("-uiTestBoardTeacher") }
        app.launch()
        tap("session_tab_board")
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "the board did not open")
        canvasFrame = canvas.frame
    }

    private var canvas: XCUIElement { app.descendants(matching: .any)["whiteboard_canvas"].firstMatch }

    private var strokeCount: Int {
        Int(app.staticTexts["uitest_board_stroke_count"].label) ?? -1
    }

    @MainActor
    private func waitForStrokes(_ count: Int) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if strokeCount == count { return true }
            usleep(200_000)
        }
        return false
    }

    /// A horizontal stroke across the lower part of the board.
    @MainActor
    private func drawOwnStroke() {
        drag(fromX: 0.2, fromY: 0.7, toX: 0.8, toY: 0.7)
    }

    /// A vertical sweep down the middle of the board.
    @MainActor
    private func sweep(fromY: CGFloat, toY: CGFloat) {
        drag(fromX: 0.5, fromY: fromY, toX: 0.52, toY: toY)
    }

    /// A drag in the board, measured from the window so the canvas's own
    /// accessibility frame plays no part, and slow enough that the board's pan
    /// recognizer sees the finger move.
    @MainActor
    private func drag(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat) {
        let frame = canvasFrame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.minX + frame.width * fromX, dy: frame.minY + frame.height * fromY))
        let end = origin.withOffset(CGVector(dx: frame.minX + frame.width * toX, dy: frame.minY + frame.height * toY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 200, thenHoldForDuration: 0.05)
    }

    @MainActor
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no \(id)")
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
