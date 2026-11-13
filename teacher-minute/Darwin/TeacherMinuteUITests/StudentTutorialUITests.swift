//
//  StudentTutorialUITests.swift
//  TeacherMinuteUITests
//
//  The tutorial twice shipped with its current page the wrong width: framed
//  to its own, already-too-wide ZStack on iOS 27 (cutting off both edges),
//  and framed to a 1-point column before its first measurement arrived (a
//  sliver of text on a cold launch). Both fixes left the same invariant —
//  the current page fills the window's width, from the very first frame and
//  on every page after it — which is what these tests check.
//
//  The app is launched with `-uiTestStudentTutorial`, which opens the
//  tutorial directly over the mock root (see `StudentTutorialUITestHarness`),
//  so no login or navigation is needed to reach it.
//
//  Everything is found by accessibility identifier, so the app's language
//  does not matter.
//

import XCTest

final class StudentTutorialUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments.append("-uiTestStudentTutorial")
        app.launch()

        XCTAssertTrue(
            pager.waitForExistence(timeout: 30),
            "the tutorial did not open"
        )
    }

    // MARK: - Tests

    /// Checked right after the wait above, with no further settling time: the
    /// page must already be the window's width on its very first frame, not
    /// some other width it later animates or snaps into.
    @MainActor
    func testTheFirstPageFillsTheScreenFromTheFirstFrame() throws {
        assertPagerFillsTheWindow()
    }

    /// Turning pages with Next and Back never resizes the strip — every page
    /// stays the same, full window width.
    @MainActor
    func testThePagerStaysTheFullWidthWhileTurningPages() throws {
        for _ in 0..<3 {
            XCTAssertTrue(tapWhenHittable(nextButton), "could not tap Next")
            assertPagerFillsTheWindow()
        }
        for _ in 0..<3 {
            XCTAssertTrue(tapWhenHittable(backButton), "could not tap Back")
            assertPagerFillsTheWindow()
        }
    }

    /// The first page has no Back, has Next and Skip, and none of the last
    /// page's controls.
    @MainActor
    func testTheFirstPageHasNextAndSkipButNoBack() throws {
        XCTAssertFalse(backButton.exists, "the first page has a Back button")
        XCTAssertTrue(nextButton.exists, "the first page has no Next button")
        XCTAssertTrue(skipButton.exists, "the first page has no Skip button")
        XCTAssertFalse(startButton.exists, "the first page already has Let's start")
        XCTAssertFalse(hideCheckbox.exists, "the first page already has the don't-show-again check box")
    }

    /// Walking every page by Next reaches a last page with Let's start and
    /// the don't-show-again check box, and no Back, Skip or Next.
    @MainActor
    func testTheLastPageHasStartAndHideButNoSkipOrNext() throws {
        for _ in 0..<9 {
            XCTAssertTrue(tapWhenHittable(nextButton), "could not tap Next")
        }
        XCTAssertTrue(
            startButton.waitForExistence(timeout: 10),
            "the last page has no Let's start button"
        )
        XCTAssertTrue(hideCheckbox.exists, "the last page has no don't-show-again check box")
        // The last page trades the Back/Next row for Let's start, as it has
        // since the tutorial was added (StudentTutorialView.controls).
        XCTAssertFalse(backButton.exists, "the last page still has a Back button")
        XCTAssertFalse(skipButton.exists, "the last page still has a Skip button")
        XCTAssertFalse(nextButton.exists, "the last page still has a Next button")
    }

    /// Skip closes the tutorial from any page.
    @MainActor
    func testSkipClosesTheTutorial() throws {
        XCTAssertTrue(tapWhenHittable(skipButton), "could not tap Skip")
        assertClosed()
    }

    /// Let's start closes the tutorial from the last page too.
    @MainActor
    func testLetsStartClosesTheTutorialFromTheLastPage() throws {
        for _ in 0..<9 {
            XCTAssertTrue(tapWhenHittable(nextButton), "could not tap Next")
        }
        XCTAssertTrue(tapWhenHittable(startButton), "could not tap Let's start")
        assertClosed()
    }

    // MARK: - Steps

    @MainActor
    private func assertPagerFillsTheWindow() {
        // The strip's identifier is handed down to the current page's
        // elements (iOS 26), and the strip as a whole spans every page, the
        // off-screen ones too. So the page is judged by what it puts on
        // screen: all of it inside the window, and its widest part across
        // most of it — a page squeezed into a column, or cut off at the
        // edges, fails one or the other.
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, 0, "the window has no width to compare against")
        let parts = app.descendants(matching: .any).matching(identifier: "student_tutorial_pager")
            .allElementsBoundByIndex.map(\.frame).filter { $0.width > 0 && $0.intersects(window) }
        XCTAssertFalse(parts.isEmpty, "the current page shows nothing")
        for part in parts {
            XCTAssertTrue(part.minX >= window.minX - 2 && part.maxX <= window.maxX + 2,
                          "part of the current page, \(part), reaches past the window \(window) — cut off at the edges")
        }
        let widest = parts.map(\.width).max() ?? 0
        XCTAssertGreaterThan(widest, window.width * 0.75,
                             "the current page is at most \(widest) points wide in a \(window.width)-point window — squeezed into a column")
    }

    @MainActor
    private func assertClosed() {
        XCTAssertTrue(
            app.staticTexts["uitest_tutorial_closed"].waitForExistence(timeout: 10),
            "the tutorial stayed open"
        )
    }

    // MARK: - Elements

    private var pager: XCUIElement { app.descendants(matching: .any)["student_tutorial_pager"] }
    private var nextButton: XCUIElement { app.buttons["student_tutorial_next"] }
    private var backButton: XCUIElement { app.buttons["student_tutorial_back"] }
    private var skipButton: XCUIElement { app.buttons["student_tutorial_skip"] }
    private var startButton: XCUIElement { app.buttons["student_tutorial_start"] }
    private var hideCheckbox: XCUIElement { app.descendants(matching: .any)["student_tutorial_hide"] }

    // MARK: - Helpers

    /// Taps once nothing covers the element — a tap on a covered element
    /// fails the test outright.
    @MainActor
    private func tapWhenHittable(_ element: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
            pause()
        } while Date() < deadline
        return false
    }

    private func pause() {
        _ = XCTWaiter.wait(for: [expectation(description: "poll")], timeout: 0.2)
    }
}
