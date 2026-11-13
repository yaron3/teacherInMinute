//
//  ProTeacherAcceptRaceUITests.swift
//  TeacherMinuteUITests
//
//  Pro Teacher losing the race for a question, against the real backend
//  running on the local Firebase emulators. QA test plan: IOS-D-13, IOS-D-14,
//  IOS-D-15.
//
//  The backend's half — exactly one accept wins — is covered by
//  `acceptRace.emulator.test.ts`. This is the app's half: what a teacher sees
//  when somebody else gets there first.
//
//   1. Another teacher accepts while the card is on screen: the card closes by
//      itself, with no dialog.
//   2. The teacher taps a card that is already stale — taken by another
//      teacher, but the removal has not reached this phone yet, as on a weak
//      network: the app says the question is gone and drops the card.
//   3. Both teachers accept at the same moment: whoever wins, the app ends in
//      the right state — in the lesson, or back on the dashboard with the card
//      gone and, if its accept reached the backend, the "already taken" dialog.
//
//  Each test signs Pro Teacher in as a brand-new teacher and plays the other
//  teacher itself, through the real `acceptInvite`. The question is written
//  straight into the emulators, already marked as sent to both teachers, so
//  dispatch stands down. Nothing reaches production: the app is launched with
//  `-firebaseEmulatorHost`, which points a debug build at the emulators.
//
//  ── Running it ──
//
//  1. Start the emulators (Java 21+), and leave them running:
//
//       JAVA_HOME=$(/usr/libexec/java_home -v 21) \
//         npm --prefix backend/Firebase/functions run emulators:app
//
//  2. Build Pro Teacher (Debug) and install it on the simulator the tests run
//     on — the test launches it by bundle id, `com.yaronj.tim`:
//
//       xcodebuild build -workspace teacher-minute/Project.xcworkspace \
//         -scheme "Pro Teacher" -configuration Debug \
//         -destination 'platform=iOS Simulator,id=<udid>' \
//         -skipMacroValidation SKIP_ACTION=none
//       xcrun simctl install <udid> <DerivedData>/Build/Products/Debug-iphonesimulator/ProTeacher.app
//
//  3. Run the class:
//
//       xcodebuild test -workspace teacher-minute/Project.xcworkspace \
//         -scheme "Instant Teacher" -destination 'platform=iOS Simulator,id=<udid>' \
//         -parallel-testing-enabled NO -skipMacroValidation SKIP_ACTION=none \
//         -only-testing:TeacherMinuteUITests/ProTeacherAcceptRaceUITests
//
//  Without the emulators the class skips itself, so a plain UI-test run is
//  unaffected.
//

import XCTest

final class ProTeacherAcceptRaceUITests: ProTeacherEmulatorTestCase {

    // MARK: - The tests

    /// IOS-D-13: another teacher takes the question while its card is up.
    @MainActor
    func testCardClosesWhenAnotherTeacherAccepts() async throws {
        try await signInAsNewTeacher()
        let qid = try await seedQuestion()
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 30), "the invite card never appeared")

        let outcome = try await backend.call("acceptInvite", as: otherTeacher, data: ["questionId": qid])
        attach("other teacher's accept", "\(outcome)")
        let acceptedBy = try await backend.strings("questions/\(qid)")?["acceptedByTeacher"]
        XCTAssertEqual(acceptedBy, otherTeacher.uid, "the other teacher's accept did not take the question")

        XCTAssertTrue(waitForDisappearance(acceptButton, timeout: 15),
                      "the card stayed on screen after another teacher took the question")
        pause(seconds: 2)
        XCTAssertFalse(dialogButton.exists, "a dialog appeared although the teacher never tapped: \(dialogText())")
    }

    /// IOS-D-15 (and IOS-D-14's losing side): the teacher taps a card that
    /// another teacher has already taken.
    @MainActor
    func testTappingAStaleCardSaysTheQuestionIsTaken() async throws {
        try await signInAsNewTeacher()
        let qid = try await seedQuestion()
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 30), "the invite card never appeared")

        _ = try await backend.call("acceptInvite", as: otherTeacher, data: ["questionId": qid])
        let takenBy = try await backend.strings("questions/\(qid)")?["acceptedByTeacher"]
        XCTAssertEqual(takenBy, otherTeacher.uid, "the other teacher's accept did not take the question")
        XCTAssertTrue(waitForDisappearance(acceptButton, timeout: 15), "the card did not close after the other accept")

        // The removal arriving late, as on a weak network: the card is back on
        // this phone although the question is taken.
        try await backend.put("teacherInvites/\(appTeacher.uid)/\(qid)", card(for: qid))
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 15), "the stale card was not shown")
        let staleAccept = try XCTUnwrap(visibleAcceptButton(), "the stale card's Accept was never tappable")
        staleAccept.tap()

        XCTAssertTrue(dialogButton.waitForExistence(timeout: 20), "no dialog after accepting a taken question")
        let text = dialogText()
        attach("dialog", text)
        XCTAssertTrue(takenMessages.contains { text.contains($0) },
                      "the dialog does not say the question was taken: \(text)")
        XCTAssertTrue(waitForDisappearance(acceptButton, timeout: 5), "the stale card stayed after the refusal")

        // The refusal changed nothing: the other teacher keeps the question.
        let question = try await backend.strings("questions/\(qid)")
        XCTAssertEqual(question?["acceptedByTeacher"], otherTeacher.uid)
        let ownInvite = try await backend.strings("questions/\(qid)/invites/\(appTeacher.uid)")
        XCTAssertEqual(ownInvite?["response"], "pending")

        dialogButton.tap()
        XCTAssertTrue(waitForDisappearance(dialogButton, timeout: 5), "the dialog did not close")
    }

    /// IOS-D-14: both teachers accept at the same moment.
    @MainActor
    func testSimultaneousAcceptEndsInOneConsistentState() async throws {
        try await signInAsNewTeacher()
        let qid = try await seedQuestion()
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 30), "the invite card never appeared")
        let visibleAccept = try XCTUnwrap(visibleAcceptButton(), "Accept was never tappable")

        // Tapped by position: if the other accept wins and the card goes first,
        // the tap lands on the dashboard instead of failing the test.
        let frame = visibleAccept.frame
        let point = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))

        let backend = backend
        let other = otherTeacher!
        let otherAccept = Task.detached {
            try await backend.call("acceptInvite", as: other, data: ["questionId": qid])
        }
        point.tap()
        let otherOutcome = try await otherAccept.value

        var winner: String?
        for _ in 0..<20 {
            winner = try await backend.strings("questions/\(qid)")?["acceptedByTeacher"]
            if winner != nil { break }
            pause()
        }
        let appWon = winner == appTeacher.uid
        attach("race", "winner=\(appWon ? "app teacher" : winner == otherTeacher.uid ? "other teacher" : "nobody") other=\(otherOutcome)")
        print("[ProTeacherAcceptRaceUITests] race won by \(appWon ? "the app" : "the other teacher")")

        XCTAssertTrue(winner == appTeacher.uid || winner == otherTeacher.uid, "nobody got the question")
        XCTAssertTrue(waitForDisappearance(acceptButton, timeout: 15), "the card stayed on screen after the race")

        if appWon {
            XCTAssertFalse(otherOutcome.succeeded, "both teachers were told they got the question")
            XCTAssertEqual(otherOutcome.reason, "question_unavailable")
            pause(seconds: 2)
            let shown = dialogButton.exists ? dialogText() : ""
            XCTAssertFalse(takenMessages.contains { shown.contains($0) },
                           "the winning app said the question was taken")
        } else {
            // The app's accept may not have left the phone before its card
            // closed. If it did, the only acceptable dialog is "already taken".
            pause(seconds: 3)
            if dialogButton.exists {
                let text = dialogText()
                attach("dialog", text)
                XCTAssertTrue(takenMessages.contains { text.contains($0) },
                              "the losing app showed something other than \"already taken\": \(text)")
            }
            let ownInvite = try await backend.strings("questions/\(qid)/invites/\(appTeacher.uid)")
            XCTAssertEqual(ownInvite?["response"], "pending", "the losing teacher's invite was marked accepted")
        }
    }
}
