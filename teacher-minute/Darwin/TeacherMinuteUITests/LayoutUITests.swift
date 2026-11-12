//
//  LayoutUITests.swift
//  TeacherMinuteUITests
//
//  IOS-E-06: the main screens of both apps on whatever simulator runs them —
//  an iPhone SE and a Pro Max in the plan — at the default text size and at
//  the largest accessibility size, against the local Firebase emulators. On
//  each screen every control that can be tapped:
//
//   - lies inside the screen, not cut off at an edge, and
//   - does not overlap another (one inside another, like a button on a card,
//     is fine).
//
//  Every screen is also kept as a screenshot, named by app, screen and text
//  size, for a review by eye.
//

import XCTest

final class LayoutUITests: ProTeacherEmulatorTestCase {

    /// The largest Dynamic Type size, for this launch only.
    private let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    @MainActor
    func testTheStudentAppFitsTheScreen() async throws {
        try await tourTheStudentApp { [self] screen in checkLayout("student", screen, "default") }
    }

    @MainActor
    func testTheTeacherAppFitsTheScreen() async throws {
        try await tourTheTeacherApp { [self] screen in checkLayout("teacher", screen, "default") }
    }

    @MainActor
    func testTheStudentAppFitsTheScreenAtTheLargestText() async throws {
        try await tourTheStudentApp(extraArguments: largestText) { [self] screen in checkLayout("student", screen, "largest") }
    }

    @MainActor
    func testTheTeacherAppFitsTheScreenAtTheLargestText() async throws {
        try await tourTheTeacherApp(extraArguments: largestText) { [self] screen in checkLayout("teacher", screen, "largest") }
    }

    // MARK: - The check

    @MainActor
    private func checkLayout(_ appName: String, _ screen: String, _ textSize: String) {
        let name = "\(appName)-\(screen)-\(textSize)"
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)

        let window = app.windows.firstMatch.frame
        guard window.width > 0 else { return XCTFail("[\(name)] no window") }
        var controls: [(label: String, frame: CGRect)] = []
        for query in [app.buttons, app.textFields, app.textViews, app.switches, app.secureTextFields] {
            for element in query.allElementsBoundByIndex where element.exists && element.isHittable {
                let frame = element.frame
                guard frame.width > 1, frame.height > 1 else { continue }
                let label = element.identifier.isEmpty ? element.label : element.identifier
                controls.append((label, frame))
            }
        }

        // Cut off: a tappable control reaching past the screen's edge.
        let screenBounds = window.insetBy(dx: -1, dy: -1)
        let cut = controls.filter { !screenBounds.contains($0.frame) }
        XCTAssertTrue(cut.isEmpty, "[\(name)] cut off at the edge: \(cut.map { "\($0.label) \($0.frame)" })")

        // Overlap: two tappable controls covering each other by more than a
        // sliver, neither inside the other.
        var overlaps: [String] = []
        for i in controls.indices {
            for j in controls.indices where j > i {
                let a = controls[i].frame, b = controls[j].frame
                guard !a.contains(b), !b.contains(a) else { continue }
                // Not a clash: the side menu lies over home, whose controls
                // XCUITest still reports as hittable; and a page's content
                // scrolls on under the tab bar.
                let names = [controls[i].label, controls[j].label]
                if names.filter({ $0.hasPrefix("side_menu_") }).count == 1 { continue }
                // The open menu's close button takes the menu button's place.
                if Set(names) == ["side_menu_close", "side_menu_button"] { continue }
                if names.contains(where: { $0.hasPrefix("tab_item_") }) { continue }
                let shared = a.intersection(b)
                guard !shared.isNull else { continue }
                let smaller = min(a.width * a.height, b.width * b.height)
                if shared.width * shared.height > smaller * 0.2 {
                    overlaps.append("\(controls[i].label) × \(controls[j].label)")
                }
            }
        }
        XCTAssertTrue(overlaps.isEmpty, "[\(name)] overlapping controls: \(overlaps)")
    }
}
