import Testing
@testable import TeacherMinute

/// What one side of a lesson is told about the other while it connects: a
/// permission prompt it can wait out, or that the other side left.
struct PeerSetupTrackerTests {
    @Test func aPermissionPromptAsksWhetherToWait() {
        var tracker = PeerSetupTracker()
        tracker.receive(.microphonePermission)

        #expect(tracker.prompt == .awaitingPermission(.microphone))
        #expect(tracker.peerAwaitedPermission == .microphone)
    }

    @Test func choosingToWaitIsNotAskedAgainWhileThePromptsLast() {
        var tracker = PeerSetupTracker()
        tracker.receive(.microphonePermission)
        tracker.waitForPeerPermission()
        #expect(tracker.prompt == nil)

        // A video lesson asks for the camera straight after the microphone.
        tracker.receive(.cameraPermission)
        #expect(tracker.prompt == nil)
        #expect(tracker.peerAwaitedPermission == .camera)
    }

    @Test func aLaterPromptAsksAgain() {
        var tracker = PeerSetupTracker()
        tracker.receive(.microphonePermission)
        tracker.waitForPeerPermission()

        tracker.receive(nil)
        #expect(tracker.prompt == nil)
        #expect(tracker.peerAwaitedPermission == nil)

        tracker.receive(.microphonePermission)
        #expect(tracker.prompt == .awaitingPermission(.microphone))
    }

    @Test func waitingWithNothingToWaitForChangesNothing() {
        var tracker = PeerSetupTracker()
        tracker.waitForPeerPermission()
        tracker.receive(.microphonePermission)

        #expect(tracker.prompt == .awaitingPermission(.microphone))
    }

    @Test func aCancelIsToldAndStays() {
        var tracker = PeerSetupTracker()
        tracker.receive(.microphonePermission)
        tracker.receive(.cancelled)
        #expect(tracker.prompt == .cancelled)
        #expect(tracker.peerAwaitedPermission == nil)

        // The question going away with the lesson changes nothing.
        tracker.receive(nil)
        tracker.questionEnded(whileConnecting: false)
        #expect(tracker.prompt == .cancelled)
    }

    @Test func theQuestionEndingWhileThisSideConnectsIsACancel() {
        var tracker = PeerSetupTracker()
        tracker.questionEnded(whileConnecting: true)

        #expect(tracker.prompt == .cancelled)
    }

    @Test func theQuestionEndingWhileTheOtherSideWasOnAPromptIsACancel() {
        // Android reads on a timer, so the "cancelled" write can fall between
        // one reading and the question disappearing.
        var tracker = PeerSetupTracker()
        tracker.receive(.cameraPermission)
        tracker.waitForPeerPermission()
        tracker.questionEnded(whileConnecting: false)

        #expect(tracker.prompt == .cancelled)
    }

    @Test func anOrdinaryEndIsNotACancel() {
        var tracker = PeerSetupTracker()
        tracker.questionEnded(whileConnecting: false)

        #expect(tracker.prompt == nil)
    }

    @Test func goingToSettingsAsksWhetherToWait() {
        var tracker = PeerSetupTracker()
        tracker.receive(.finishingSetup)

        #expect(tracker.prompt == .finishingSetup)
        #expect(tracker.isPeerFinishingSetup)
        #expect(tracker.peerAwaitedPermission == nil)
    }

    @Test func choosingToWaitForSettingsIsNotAskedAgainUntilTheyAreBack() {
        var tracker = PeerSetupTracker()
        tracker.receive(.finishingSetup)
        tracker.waitForPeerPermission()
        #expect(tracker.prompt == nil)
        // Still said on screen while they are away.
        #expect(tracker.isPeerFinishingSetup)

        tracker.receive(nil)
        #expect(!tracker.isPeerFinishingSetup)

        tracker.receive(.finishingSetup)
        #expect(tracker.prompt == .finishingSetup)
    }

    @Test func waitingOnAPromptCoversTheTripToSettingsThatFollows() {
        var tracker = PeerSetupTracker()
        tracker.receive(.microphonePermission)
        tracker.waitForPeerPermission()

        tracker.receive(.finishingSetup)
        #expect(tracker.prompt == nil)
        #expect(tracker.isPeerFinishingSetup)
    }

    @Test func theQuestionEndingWhileTheOtherSideIsInSettingsIsACancel() {
        var tracker = PeerSetupTracker()
        tracker.receive(.finishingSetup)
        tracker.waitForPeerPermission()
        tracker.questionEnded(whileConnecting: false)

        #expect(tracker.prompt == .cancelled)
        #expect(!tracker.isPeerFinishingSetup)
    }

    @Test func signalsReadBackAsWritten() {
        #expect(ConnectionSetupSignal(rawValue: "microphone") == .microphonePermission)
        #expect(ConnectionSetupSignal(rawValue: "camera") == .cameraPermission)
        #expect(ConnectionSetupSignal(rawValue: "settings") == .finishingSetup)
        #expect(ConnectionSetupSignal(rawValue: "cancelled") == .cancelled)
        // Something a newer app writes is ignored rather than misread.
        #expect(ConnectionSetupSignal(rawValue: "somethingNewer") == nil)
        #expect(ConnectionSetupSignal.awaiting(.camera) == .cameraPermission)
    }
}

/// Each side is told about the other one, in its own words.
@MainActor
struct PeerSetupPromptCopyTests {
    @Test func theStudentIsToldAboutTheirTeacher() {
        let viewModel = MockChatSessionViewModel(role: "student")

        #expect(
            viewModel.peerSetupTitle(for: .cancelled)
                == LocalizationSupport.localized("Your teacher cancelled the session.")
        )
        #expect(
            viewModel.peerSetupMessage(for: .awaitingPermission(.camera))
                == LocalizationSupport.localized(
                    "Your teacher was asked to allow access to their camera. Do you want to wait until they approve?"
                )
        )
        #expect(
            viewModel.peerSetupTitle(for: .finishingSetup)
                == LocalizationSupport.localized("Waiting for your teacher")
        )
        #expect(
            viewModel.peerSetupMessage(for: .finishingSetup)
                == LocalizationSupport.localized(
                    "Your teacher needs to finish setting up and will join shortly. Do you want to wait?"
                )
        )
    }

    @Test func theTeacherIsToldAboutTheStudent() {
        let viewModel = MockChatSessionViewModel(role: "teacher")

        #expect(
            viewModel.peerSetupTitle(for: .awaitingPermission(.microphone))
                == LocalizationSupport.localized("Waiting for the student")
        )
        #expect(
            viewModel.peerSetupMessage(for: .cancelled)
                == LocalizationSupport.localized("You can take the next question.")
        )
    }

    @Test func waitingTakesTheQuestionDownButKeepsTheReminder() {
        let viewModel = MockChatSessionViewModel(role: "teacher")
        var updates = 0
        viewModel.onPeerSetupUpdated = { updates += 1 }

        viewModel.simulatePeerSetupSignal(.microphonePermission)
        #expect(viewModel.peerSetupPrompt == .awaitingPermission(.microphone))

        viewModel.waitForPeerPermission()
        #expect(viewModel.peerSetupPrompt == nil)
        #expect(viewModel.peerAwaitedPermission == .microphone)
        #expect(updates == 2)
    }
}
