//
//  AppearanceUITests.swift
//  TeacherMinuteUITests
//
//  IOS-G-03: both apps under the system's Light and Dark appearance, against
//  the local Firebase emulators. The apps draw on the brand's dark ground
//  whatever the system says (`.preferredColorScheme(.dark)` in
//  TeacherMinuteApp), so on every main screen:
//
//   - the system's Light and Dark give the same picture, and
//   - no screen is mostly white — no light screen, no white flash on the
//     switch (the switch happens on the screen, then it is captured at once).
//
//  Every capture is kept in the result bundle, named by app, screen and
//  appearance, for a review by eye.
//

import XCTest

final class AppearanceUITests: ProTeacherEmulatorTestCase {

    override func tearDownWithError() throws {
        XCUIDevice.shared.appearance = .dark
        try super.tearDownWithError()
    }

    /// Instant Teacher, as a guest.
    @MainActor
    func testTheStudentAppLooksTheSameInLightAndDark() async throws {
        try await tourTheStudentApp { [self] screen in check("student", screen) }
    }

    /// Pro Teacher, signed in as a new teacher.
    @MainActor
    func testTheTeacherAppLooksTheSameInLightAndDark() async throws {
        try await tourTheTeacherApp { [self] screen in check("teacher", screen) }
    }

    // MARK: - The check

    /// The screen under the system's Light, then Dark: kept, compared, and
    /// each checked for a mostly white picture.
    @MainActor
    private func check(_ appName: String, _ screen: String) {
        XCUIDevice.shared.appearance = .light
        let light = capture("\(appName)-\(screen)-light")
        XCUIDevice.shared.appearance = .dark
        let dark = capture("\(appName)-\(screen)-dark")
        guard let light, let dark else {
            XCTFail("[\(appName) \(screen)] could not read the screenshots")
            return
        }
        let lightWhite = Self.whiteShare(light)
        let darkWhite = Self.whiteShare(dark)
        XCTAssertLessThan(lightWhite, 0.25, "[\(appName) \(screen)] is \(Int(lightWhite * 100))% white under the system's Light")
        XCTAssertLessThan(darkWhite, 0.25, "[\(appName) \(screen)] is \(Int(darkWhite * 100))% white under the system's Dark")
        let difference = Self.difference(light, dark)
        XCTAssertLessThan(difference, 0.06,
                          "[\(appName) \(screen)] differs by \(String(format: "%.3f", difference)) between Light and Dark")
    }

    @MainActor
    private func capture(_ name: String) -> CGImage? {
        pause(seconds: 1)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return shot.image.cgImage
    }

    /// The screen below the status bar as a small grid of brightness values,
    /// 0 to 1.
    private static func grid(_ image: CGImage, columns: Int = 36, rows: Int = 72) -> [Double] {
        let space = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: columns * rows)
        let top = image.height / 14 // past the status bar, whose clock moves
        guard let cropped = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: image.height - top)),
              let context = CGContext(data: &pixels, width: columns, height: rows, bitsPerComponent: 8,
                                      bytesPerRow: columns, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return [] }
        context.interpolationQuality = .medium
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        return pixels.map { Double($0) / 255 }
    }

    /// The share of the screen that is near white.
    static func whiteShare(_ image: CGImage) -> Double {
        let cells = grid(image)
        guard !cells.isEmpty else { return 1 }
        return Double(cells.filter { $0 > 0.85 }.count) / Double(cells.count)
    }

    /// The mean brightness difference between two pictures of a screen.
    static func difference(_ a: CGImage, _ b: CGImage) -> Double {
        let first = grid(a), second = grid(b)
        guard first.count == second.count, !first.isEmpty else { return 1 }
        return zip(first, second).map { abs($0 - $1) }.reduce(0, +) / Double(first.count)
    }
}
