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

final class ProTeacherAcceptRaceUITests: XCTestCase {

    private let backend = EmulatorBackend()
    private var app: XCUIApplication!

    /// The teacher signed in to the app, and the one this test plays.
    private var appTeacher: EmulatorBackend.Account!
    private var otherTeacher: EmulatorBackend.Account!
    private var student: EmulatorBackend.Account!
    /// The question this test seeded.
    private var currentQid = ""

    private let topic = "algebra"
    private let questionText = "Emulator race: solve 2x + 3 = 11"

    /// The dialog's message in either language; the app may run with Remote
    /// Config's Hebrew copy cached or on its English defaults.
    private let takenMessages = ["Another teacher already answered it", "מורה אחר/ת כבר ענה/תה עליה"]

    private let systemPromptHosts = [
        "com.apple.springboard",
        "com.apple.AuthenticationServicesUI",
        "com.apple.Passwords",
        "com.apple.CredentialSharingService",
    ].map { XCUIApplication(bundleIdentifier: $0) }
    private let promptDismissLabels = ["Not Now", "Don't Allow"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        // A question left searching would be backfilled to the next test's
        // teacher the moment it comes online, putting a second card on its
        // dashboard. Waited for on a background queue, since XCTest's own
        // waits hold the main thread.
        guard !currentQid.isEmpty else { return }
        let done = DispatchSemaphore(value: 0)
        let backend = backend
        let qid = currentQid
        Task.detached {
            try? await backend.merge("questions/\(qid)", ["status": "unanswered"])
            done.signal()
        }
        _ = done.wait(timeout: .now() + 15)
    }

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

    // MARK: - Scene

    /// Two new teachers and a student on the emulators, and the app signed in
    /// as the first teacher on its dashboard.
    @MainActor
    private func signInAsNewTeacher() async throws {
        guard await backend.isRunning() else {
            throw XCTSkip("Firebase emulators not running; see the header for how to start them")
        }
        appTeacher = try await backend.createAccount(prefix: "race.app-teacher")
        otherTeacher = try await backend.createAccount(prefix: "race.other-teacher")
        student = try await backend.createAccount(prefix: "race.student")
        for (account, name) in [(appTeacher!, "Race App Teacher"), (otherTeacher!, "Race Other Teacher")] {
            try await backend.merge("users/\(account.uid)", [
                "role": "teacher",
                "fullName": name,
                "phoneNumber": "+972500000000",
                "subjectSelections": ["math": [topic]],
            ])
        }
        try await backend.merge("users/\(student.uid)", ["role": "student", "fullName": "Race Student"])
        attach("accounts", "app teacher \(appTeacher.email)\nother teacher \(otherTeacher.email)")

        addUIInterruptionMonitor(withDescription: "iOS system prompt") { [promptDismissLabels] alert in
            for label in promptDismissLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app = XCUIApplication(bundleIdentifier: "com.yaronj.tim")
        app.launchArguments += [
            "-firebaseEmulatorHost", EmulatorBackend.host,
            // Whatever an earlier run left signed in, start at the welcome screen.
            "-firebaseEmulatorSignOut", "YES",
        ]
        app.launch()

        let logIn = app.buttons["welcome_log_in"]
        let dashboard = app.switches["availability_toggle"]
        // A tap while the welcome screen is still animating in does nothing,
        // so it is repeated until the form opens.
        let emailField = app.textFields["email_input"]
        for _ in 0..<5 where !emailField.exists {
            XCTAssertTrue(tapWhenHittable(logIn, "the welcome screen's Log in"),
                          "the welcome screen's Log in never appeared")
            _ = emailField.waitForExistence(timeout: 5)
        }

        type(appTeacher.email, into: app.textFields["email_input"], "the login email field")
        type(appTeacher.password, into: app.secureTextFields["password_input"], "the login password field")
        dismissKeyboard()
        XCTAssertTrue(tapWhenHittable(app.buttons["login_submit"], "Log in"), "Log in was never tappable")

        let reached = waitForAny([dashboard, app.buttons["availability_toggle"]], timeout: 90) { [self] in
            _ = tapIfPresent(app.buttons["permissions_setup_skip"])
            _ = tapIfPresent(app.buttons["Not Now"])
        }
        XCTAssertNotNil(reached, "signing in did not reach the teacher dashboard")
    }

    /// A searching question already sent to both teachers, with both cards
    /// delivered — what dispatch leaves behind.
    private func seedQuestion() async throws -> String {
        let qid = "race-\(UUID().uuidString.prefix(8).lowercased())"
        currentQid = qid
        let now = Date()
        for teacher in [appTeacher!, otherTeacher!] {
            try await backend.merge("questions/\(qid)/invites/\(teacher.uid)", [
                "teacherUid": teacher.uid,
                "response": "pending",
                "wave": 1,
                "invitedAt": now,
                "expiresAt": now.addingTimeInterval(180),
            ])
        }
        try await backend.merge("questions/\(qid)", [
            "studentUid": student.uid,
            "status": "searching",
            "topic": topic,
            "text": questionText,
            "conversationType": "text",
            "dispatchWave": 1,
            "alreadyInvited": [appTeacher.uid, otherTeacher.uid],
            // The Cloud Tasks emulator runs a delayed task at once, so the
            // abandoned-lesson check that production runs minutes after an
            // accept would write the lesson off within a second — and a late
            // tap would then be told the student cancelled. A student who has
            // already joined a started lesson keeps the check away.
            "joinedParticipants": [student.uid],
            "lessonId": "\(qid)-lesson",
            "createdAt": now,
            "updatedAt": now,
        ])
        for teacher in [appTeacher!, otherTeacher!] {
            try await backend.put("teacherInvites/\(teacher.uid)/\(qid)", card(for: qid))
        }
        return qid
    }

    private func card(for qid: String) -> [String: Any] {
        [
            "questionId": qid,
            "topic": topic,
            "text": questionText,
            "expiresAt": Int(Date().addingTimeInterval(180).timeIntervalSince1970 * 1000),
            "wave": 1,
            "studentId": student.uid,
            "studentName": "Race Student",
            "conversationType": "text",
            "pricePerMinuteCents": 50,
        ]
    }

    // MARK: - App

    /// The test's own question's Accept. The dashboard can list other
    /// questions too, and the incoming-question overlay repeats the newest
    /// card, so there may be two of these; any one of them existing means the
    /// card is still up.
    private var acceptButton: XCUIElement {
        app.buttons.matching(identifier: "invite_accept_\(currentQid)").firstMatch
    }

    /// The copy of this question's Accept the teacher can actually tap.
    @MainActor
    private func visibleAcceptButton(timeout: TimeInterval = 30) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let copies = app.buttons.matching(identifier: "invite_accept_\(currentQid)").allElementsBoundByIndex
            if let visible = copies.first(where: { $0.exists && $0.isHittable }) { return visible }
            if !dismissSystemPromptIfPresent() { pause(seconds: 0.5) }
        } while Date() < deadline
        return nil
    }
    private var dialogButton: XCUIElement { app.buttons["dialog_confirm_button"] }

    private func dialogText() -> String {
        app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
    }

    @MainActor
    private func type(_ text: String, into field: XCUIElement, _ described: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 20), "no \(described)")
        XCTAssertTrue(tapWhenHittable(field, described), "\(described) was never tappable")
        field.typeText(text)
    }

    @MainActor
    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        _ = waitForDisappearance(app.keyboards.firstMatch, timeout: 3)
    }

    // MARK: - Waiting and tapping

    @MainActor
    private func dismissSystemPromptIfPresent() -> Bool {
        for host in systemPromptHosts + [app].compactMap({ $0 }) {
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

    /// Taps once nothing covers the element: `tap()` on a covered element
    /// fails the test outright.
    @MainActor
    private func tapWhenHittable(_ element: XCUIElement, _ described: String, timeout: TimeInterval = 30) -> Bool {
        guard waitForHittable(element, timeout: timeout) else { return false }
        element.tap()
        return true
    }

    @MainActor
    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.isHittable { return true }
            if !dismissSystemPromptIfPresent() { pause(seconds: 0.5) }
        } while Date() < deadline
        return false
    }

    @MainActor
    private func tapIfPresent(_ element: XCUIElement) -> Bool {
        guard element.exists && element.isHittable else { return false }
        element.tap()
        return true
    }

    private func waitForAny(
        _ elements: [XCUIElement],
        timeout: TimeInterval,
        whileWaiting: () -> Void = {}
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let found = elements.first(where: \.exists) { return found }
            whileWaiting()
            pause(seconds: 0.5)
        } while Date() < deadline
        return nil
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline {
            pause(seconds: 0.5)
        }
        return !element.exists
    }

    private func pause(seconds: TimeInterval = 1) {
        _ = XCTWaiter.wait(for: [expectation(description: "poll")], timeout: seconds)
    }

    private func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
