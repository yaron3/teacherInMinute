//
//  ProTeacherHeaderUITests.swift
//  TeacherMinuteUITests
//
//  IT-29: the dashboard header's bell and menu button stay at the header's
//  edges after the messages panel is opened and closed. They used to drift
//  toward the centre.
//
//  Runs on the local Firebase emulators, signed in as a new teacher, like the
//  other Pro Teacher tests.
//

import XCTest

final class ProTeacherHeaderUITests: ProTeacherEmulatorTestCase {

    @MainActor
    func testHeaderButtonsStayAtTheEdgesAfterTheMessagesPanel() async throws {
        try await signInAsNewTeacher()

        let bell = app.buttons["messages_button"]
        XCTAssertTrue(bell.waitForExistence(timeout: 30), "no bell on the dashboard header")
        let menu = menuButton(beside: bell)
        XCTAssertNotNil(menu, "no menu button beside the bell")

        let bellBefore = bell.frame
        let menuBefore = menu?.frame ?? .zero
        keep("IT-29 header before the messages panel")

        // iOS's "Save Password?" prompt lands after sign-in, on its own schedule,
        // and covers the header. Wait until the bell is hittable, dismissing
        // prompts as they appear, rather than tapping through them.
        // The prompt is a system dialog, so it may sit in SpringBoard's tree
        // rather than the app's.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(30)
        while !bell.isHittable && Date() < deadline {
            if app.buttons["Not Now"].exists {
                app.buttons["Not Now"].tap()
            } else if springboard.buttons["Not Now"].exists {
                springboard.buttons["Not Now"].tap()
            }
            pause(seconds: 0.5)
        }
        XCTAssertTrue(bell.isHittable, "the bell stayed covered")
        XCTAssertTrue(tapWhenHittable(bell, "the bell"), "the bell was never tappable")
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 10), "the bell did not open the messages panel")
        pause(seconds: 2)
        keep("IT-29 messages panel open")
        dismissMessagesPanel()
        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 10), "the messages panel did not close")
        pause(seconds: 2)
        keep("IT-29 header after the messages panel")

        XCTAssertTrue(bell.waitForExistence(timeout: 10), "the bell is gone after closing the panel")
        XCTAssertEqual(bell.frame.minX, bellBefore.minX, accuracy: 1, "the bell moved after closing the panel")
        XCTAssertEqual(bell.frame.minY, bellBefore.minY, accuracy: 1, "the bell moved after closing the panel")
        if let menuAfter = menuButton(beside: bell)?.frame {
            XCTAssertEqual(menuAfter.minX, menuBefore.minX, accuracy: 1, "the menu button moved after closing the panel")
            XCTAssertEqual(menuAfter.maxX, menuBefore.maxX, accuracy: 1, "the menu button moved after closing the panel")
        } else {
            XCTFail("the menu button is gone after closing the panel")
        }
    }

    // MARK: - Helpers

    /// The button on the bell's row, to its right: the header's menu.
    @MainActor
    private func menuButton(beside bell: XCUIElement) -> XCUIElement? {
        let row = bell.frame
        return app.buttons.allElementsBoundByIndex.first { candidate in
            candidate.exists
                && candidate.frame.minX > row.maxX
                && abs(candidate.frame.midY - row.midY) < 6
        }
    }

    /// Closes the messages sheet by dragging it down, from its top edge.
    @MainActor
    private func dismissMessagesPanel() {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    @MainActor
    private func keep(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
