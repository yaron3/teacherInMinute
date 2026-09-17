//
//  SessionTypeSwitchUITests.swift
//  TeacherMinuteUITests
//
//  Switches a running lesson between text, audio and video, from this side
//  and from the other.
//
//  A real lesson needs a teacher to accept a real question, and a test must
//  never send one — dispatch fans it out to real teachers (see the project's
//  CLAUDE.md). So the app is launched with `-uiTestSessionTypeSwitch`, which
//  opens the lesson screen over a mock session in debug builds, with buttons
//  that play the other participant.
//
//  The mock has no room to join, so audio and video never actually connect.
//  What is checked is the lesson's own state: which type is selected, and the
//  controls and tabs that type brings with it.
//
//  Everything is found by accessibility identifier, so the app's language does
//  not matter.
//

import XCTest

final class SessionTypeSwitchUITests: XCTestCase {

    private var app: XCUIApplication!

    /// The switch joins a LiveKit room, which starts the microphone — so iOS
    /// may ask for it. The test needs no audio, and turns it down.
    private let systemPromptHosts = [
        "com.apple.springboard",
    ].map { XCUIApplication(bundleIdentifier: $0) }
    private let promptDismissLabels = ["Don't Allow"]

    override func setUpWithError() throws {
        continueAfterFailure = false

        addUIInterruptionMonitor(withDescription: "iOS system prompt") { [promptDismissLabels] alert in
            for label in promptDismissLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app = XCUIApplication()
        app.launchArguments.append("-uiTestSessionTypeSwitch")
        app.launch()

        XCTAssertTrue(
            button("session_type_change").waitForExistence(timeout: 30),
            "the lesson screen did not open"
        )
    }

    // MARK: - Tests

    /// This side picks each type in turn from the header.
    @MainActor
    func testSwitchingTheSessionTypeFromTheHeader() throws {
        assertTextSession()

        switchTo("audio")
        assertAudioSession()

        switchTo("video")
        assertVideoSession()

        switchTo("text")
        assertTextSession()
    }

    /// The other side switches. Moving up waits for this side's answer;
    /// moving down happens straight away.
    @MainActor
    func testFollowingTheOtherSidesSwitch() throws {
        assertTextSession()

        // Turned down: the lesson stays text here.
        peerSwitches(to: "video")
        answerPeerDialog(accept: false)
        assertTextSession()

        // Accepted.
        peerSwitches(to: "audio")
        answerPeerDialog(accept: true)
        assertAudioSession()

        peerSwitches(to: "video")
        answerPeerDialog(accept: true)
        assertVideoSession()

        // Down to text: no question asked.
        peerSwitches(to: "text")
        assertNoDialog()
        assertTextSession()
    }

    // MARK: - Steps

    @MainActor
    private func switchTo(_ type: String) {
        openPicker()
        let chip = button("session_type_\(type)")
        XCTAssertTrue(tapWhenHittable(chip), "could not tap the \(type) chip")
        // The strip closes once the switch has gone through.
        XCTAssertTrue(waitForDisappearance(chip), "the type picker stayed open after choosing \(type)")
        assertSelected(type)
    }

    /// Reopens the picker to read which chip it marks, then closes it again.
    @MainActor
    private func assertSelected(_ type: String) {
        openPicker()
        for candidate in ["text", "audio", "video"] {
            let chip = button("session_type_\(candidate)")
            if candidate == type {
                XCTAssertTrue(chip.isSelected, "\(type) is not marked as the session type")
            } else {
                XCTAssertFalse(chip.isSelected, "\(candidate) is still marked alongside \(type)")
            }
        }
        XCTAssertTrue(tapWhenHittable(button("session_type_change")), "could not close the type picker")
        XCTAssertTrue(
            waitForDisappearance(button("session_type_text")),
            "the type picker did not close"
        )
    }

    @MainActor
    private func openPicker() {
        let textChip = button("session_type_text")
        if textChip.exists { return }
        XCTAssertTrue(tapWhenHittable(button("session_type_change")), "could not tap Change")
        XCTAssertTrue(textChip.waitForExistence(timeout: 10), "the type picker did not open")
    }

    @MainActor
    private func peerSwitches(to type: String) {
        XCTAssertTrue(
            tapWhenHittable(button("uitest_peer_switch_\(type)")),
            "could not play the other side switching to \(type)"
        )
    }

    @MainActor
    private func answerPeerDialog(accept: Bool) {
        let confirm = button("dialog_confirm_button")
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no dialog asked to follow the other side")
        let answer = accept ? confirm : button("dialog_cancel_button")
        XCTAssertTrue(tapWhenHittable(answer), "could not answer the dialog")
        XCTAssertTrue(waitForDisappearance(confirm), "the dialog stayed up after answering")
    }

    @MainActor
    private func assertNoDialog() {
        pause()
        XCTAssertFalse(button("dialog_confirm_button").exists, "moving down asked for permission it does not need")
    }

    // MARK: - What each type looks like

    @MainActor
    private func assertTextSession() {
        XCTAssertTrue(waitForDisappearance(button("session_mic_toggle")), "a text session still shows the microphone")
        XCTAssertFalse(button("session_camera_toggle").exists, "a text session shows the camera")
        XCTAssertFalse(button("session_tab_video").exists, "a text session has a Video tab")
        XCTAssertTrue(button("session_tab_chat").exists, "the Chat tab is missing")
    }

    @MainActor
    private func assertAudioSession() {
        XCTAssertTrue(button("session_mic_toggle").waitForExistence(timeout: 10), "an audio session has no microphone control")
        XCTAssertTrue(waitForDisappearance(button("session_camera_toggle")), "an audio session shows the camera")
        XCTAssertTrue(waitForDisappearance(button("session_tab_video")), "an audio session has a Video tab")
    }

    @MainActor
    private func assertVideoSession() {
        XCTAssertTrue(button("session_camera_toggle").waitForExistence(timeout: 10), "a video session has no camera control")
        XCTAssertTrue(button("session_mic_toggle").exists, "a video session has no microphone control")
        XCTAssertTrue(button("session_tab_video").exists, "a video session has no Video tab")
    }

    // MARK: - Helpers

    private func button(_ identifier: String) -> XCUIElement {
        app.buttons[identifier]
    }

    /// Taps once nothing covers the element, clearing system prompts while it
    /// waits — a tap on a covered element fails the test outright.
    @MainActor
    private func tapWhenHittable(_ element: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
            if !dismissSystemPromptIfPresent() {
                pause()
            }
        } while Date() < deadline
        return false
    }

    @MainActor
    @discardableResult
    private func dismissSystemPromptIfPresent() -> Bool {
        for host in systemPromptHosts + [app!] {
            for label in promptDismissLabels {
                let button = host.buttons[label]
                if button.exists && button.isHittable {
                    button.tap()
                    return true
                }
            }
        }
        return false
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    private func pause() {
        _ = XCTWaiter.wait(for: [expectation(description: "poll")], timeout: 1)
    }
}
