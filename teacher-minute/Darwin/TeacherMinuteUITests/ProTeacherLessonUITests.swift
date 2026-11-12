//
//  ProTeacherLessonUITests.swift
//  TeacherMinuteUITests
//
//  The teacher's half of a live lesson, run on a second simulator at the same
//  time as the student's half (StudentLessonUITests) on the first, both against
//  the local Firebase emulators. `scripts/run-lesson-tests.sh` creates the
//  teacher account, builds once and starts the two together. QA test plan:
//
//   IOS-L-03  the student ends the lesson: the teacher leaves it too and is
//             free again (no busy mark), back on the dashboard, and finds the
//             lesson in Lessons (IOS-R-05), and in this month's earnings
//             (IOS-M-07)
//   IOS-L-04  the teacher ends the lesson and is free again
//   IOS-D-12  taking the card: in the lesson, the question accepted by this
//             teacher in Firestore and in the live question
//   IOS-L-02  in the first: a message each way, in order, and the teacher's
//             stroke on the board reaching the student
//
//  The two halves meet only through the emulators: this one signs in, goes
//  online, accepts the first card that reaches it, and stays in the lesson
//  until the student ends it. The lesson runs as text — the simulators have no
//  audio to connect between them.
//
//  Skipped unless the run sets LESSON_TEACHER_EMAIL, LESSON_TEACHER_PASSWORD
//  and LESSON_TEACHER_UID (xcodebuild: TEST_RUNNER_LESSON_TEACHER_EMAIL, …).
//

import XCTest

final class ProTeacherLessonUITests: ProTeacherEmulatorTestCase {

    /// IOS-L-03 (and R-05) — pairs with the student's
    /// testTakingALessonThenEndingAndRatingIt and
    /// testEndingALessonThenReportingAndBlockingTheTeacher: the student ends
    /// the lesson; the teacher is freed, back on the dashboard, and finds the
    /// lesson in Lessons.
    @MainActor
    func testTeachingALessonTheStudentEnds() async throws {
        let (uid, qid) = try await joinTheStudentsLesson()
        try await chatThenDraw(qid)
        try await waitForTheStudentToEnd(uid: uid, qid: qid)
    }

    /// Pairs with the student's
    /// testEndingALessonThenReportingAndBlockingTheTeacher: as
    /// testTeachingALessonTheStudentEnds, without the chat, which that half
    /// does not hold.
    @MainActor
    func testTeachingALessonTheStudentEndsAndReports() async throws {
        let (uid, qid) = try await joinTheStudentsLesson()
        try await waitForTheStudentToEnd(uid: uid, qid: qid)
    }

    @MainActor
    private func waitForTheStudentToEnd(uid: String, qid: String) async throws {
        let end = app.buttons["session_end_button"]
        try require(waitForDisappearance(end, timeout: 300), "the lesson never ended for the teacher")
        try await expectFreeOnTheDashboard(uid)
        try await expectInLessons("Asking Student", qid: qid)
        try await expectInEarnings(uid)
    }

    /// IOS-L-04 — pairs with the student's
    /// testTakingALessonTheTeacherEndsThenSkippingTheRating: the teacher ends
    /// the lesson after 35 seconds (long enough for the student to be offered
    /// a rating) and is free again.
    @MainActor
    func testTeachingALessonAndEndingIt() async throws {
        let (uid, _) = try await joinTheStudentsLesson()
        pause(seconds: 35)
        let end = app.buttons["session_end_button"]
        try require(tapWhenHittable(end, "End"), "End was never tappable")
        try require(tapWhenHittable(app.buttons["chat_end_prompt_primary"], "the end confirmation"), "ending asked nothing")
        try require(waitForDisappearance(end, timeout: 60), "ending did not leave the lesson")
        try await expectFreeOnTheDashboard(uid)
    }

    // MARK: - Steps

    /// Signs in as the run's teacher, comes online, waits for the student's
    /// text question and takes it; returns the teacher's uid and the
    /// question once in the lesson.
    @MainActor
    private func joinTheStudentsLesson() async throws -> (uid: String, qid: String) {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["LESSON_TEACHER_EMAIL"], let password = env["LESSON_TEACHER_PASSWORD"],
              let uid = env["LESSON_TEACHER_UID"] else {
            throw XCTSkip("run through scripts/ui-tests/run_lesson_tests.sh, which sets the lesson teacher's account")
        }
        guard await backend.isRunning() else { throw XCTSkip("Firebase emulators not running") }
        addUIInterruptionMonitor(withDescription: "iOS system prompt") { [promptDismissLabels] alert in
            for label in promptDismissLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        launchApp()
        // On a fresh simulator the welcome screen's Log in can sit below the
        // fold.
        let logIn = app.buttons["welcome_log_in"]
        _ = logIn.waitForExistence(timeout: 30)
        for _ in 0..<4 where !(logIn.exists && logIn.isHittable) { app.swipeUp() }
        openLoginForm()
        submitLogin(email: email, password: password)
        try require(waitForDashboard(timeout: 90), "signing in did not reach the dashboard")

        // A teacher who refuses notifications is taken offline, and the shared
        // helpers answer system prompts "Don't Allow". On a fresh simulator
        // the prompt comes up now: allowed here, before they see it.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 20) { allow.tap() }
        var online = false
        for attempt in 0..<40 where !online {
            online = try await backend.exists("onlineTeachers/\(uid)")
            if !online {
                // Switched on by hand if it did not come online by itself.
                if attempt == 10 { _ = tapIfPresent(app.buttons["availability_toggle"]) }
                if allow.exists { allow.tap() }
                pause(seconds: 1)
            }
        }
        try require(online, "the teacher never came online")

        // The student's half asks once this teacher is listed online; the card
        // that reaches this teacher names the question.
        var qid = ""
        let asked = Date().addingTimeInterval(300)
        repeat {
            qid = try await backend.childKeys("teacherInvites/\(uid)").first ?? ""
            if qid.isEmpty { pause(seconds: 1) }
        } while qid.isEmpty && Date() < asked
        try require(!qid.isEmpty, "no question reached the teacher")
        currentQid = qid
        attach("question", qid)
        // The student's half picks a text lesson on its search screen: taken
        // only once it has, since the simulators have no audio between them.
        var type = ""
        let chosen = Date().addingTimeInterval(120)
        repeat {
            type = (try await backend.strings("questions/\(qid)"))?["conversationType"] ?? ""
            if type != "text" { pause(seconds: 1) }
        } while type != "text" && Date() < chosen
        try require(type == "text", "the student never chose a text lesson (\(type))")
        let accept = visibleAcceptButton(timeout: 60)
        try require(accept != nil, "the question's card never showed")
        accept?.tap()
        // The base class's tearDown marks currentQid unanswered, for questions
        // a test left searching; this one becomes a lesson the student's half
        // still checks, so it must not be touched.
        currentQid = ""

        let end = app.buttons["session_end_button"]
        let textOnly = app.buttons["connection_setup_continue_as_text"]
        let entered = waitForAny([end, textOnly], timeout: 90) { [self] in _ = dismissSystemPromptIfPresent() }
        if entered == textOnly { _ = tapWhenHittable(textOnly, "Continue with text only") }
        try require(end.waitForExistence(timeout: 90), "the teacher never entered the lesson")
        // IOS-D-12: the accept is this teacher's, in both stores.
        let accepted = try await backend.fields("questions/\(qid)") ?? [:]
        XCTAssertEqual((accepted["acceptedByTeacher"] as? [String: Any])?["stringValue"] as? String, uid,
                       "the question is not recorded as accepted by this teacher")
        let status = (accepted["status"] as? [String: Any])?["stringValue"] as? String ?? ""
        XCTAssertFalse(["searching", "unanswered", "cancelled", ""].contains(status), "the accepted question is \(status)")
        let live = try await backend.strings("questions/\(qid)") ?? [:]
        XCTAssertEqual(live["acceptedByTeacher"], uid, "the live question does not name this teacher")
        return (uid, qid)
    }

    /// IOS-L-02, the teacher's side: a message to the student, the student's
    /// answer back below it, then a stroke on the board, which reaches the
    /// lesson's board for the student to see.
    @MainActor
    private func chatThenDraw(_ qid: String) async throws {
        let chat = app.buttons["session_tab_chat"]
        _ = tapIfPresent(chat)
        let field = app.textFields["chat_message_field"]
        try require(tapWhenHittable(field, "the message field"), "no message field in the lesson")
        field.typeText(Self.teacherMessage)
        try require(tapWhenHittable(app.buttons["chat_send_button"], "Send"), "the message could not be sent")
        dismissKeyboard()

        let mine = app.staticTexts[Self.teacherMessage]
        let reply = app.staticTexts[Self.studentReply]
        try require(reply.waitForExistence(timeout: 120), "the student's reply never reached the teacher")
        XCTAssertTrue(mine.exists && mine.frame.minY < reply.frame.minY, "the messages are out of order")

        try require(tapWhenHittable(app.buttons["session_tab_board"], "the Board tab"), "no Board tab in the lesson")
        pause(seconds: 1)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
        from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.55)))
        var strokes: [String] = []
        for _ in 0..<20 where strokes.isEmpty {
            strokes = try await backend.childKeys("questions/\(qid)/board/strokes")
            if strokes.isEmpty { pause(seconds: 0.5) }
        }
        XCTAssertFalse(strokes.isEmpty, "the teacher's stroke never reached the board")
        _ = tapIfPresent(chat)
    }

    /// What the two halves say to each other (the student's half has the same).
    static let teacherMessage = "Let's start with the x terms."
    static let studentReply = "OK, I moved them to one side."

    /// No busy mark, and past whatever summary follows, the dashboard.
    @MainActor
    private func expectFreeOnTheDashboard(_ uid: String) async throws {
        var busy: Any? = "busy"
        let deadline = Date().addingTimeInterval(30)
        repeat {
            busy = try await backend.value("teachers/\(uid)/busy")
            if busy != nil { pause(seconds: 0.5) }
        } while busy != nil && Date() < deadline
        XCTAssertNil(busy, "the teacher is still marked busy after the lesson")
        let home = waitForAny([app.buttons["availability_toggle"], app.switches["availability_toggle"]], timeout: 60) { [self] in
            for label in ["Done", "סיום", "OK", "אישור"] { _ = tapIfPresent(app.buttons[label]) }
            _ = tapIfPresent(app.buttons["dialog_confirm_button"])
        }
        if home == nil { attach("after the lesson", app.debugDescription) }
        try require(home != nil, "the teacher did not get back to the dashboard")
    }

    /// IOS-R-05, the teacher's side: the lesson in the Lessons tab, by the
    /// student's name, with the length and the earnings the backend settled
    /// it at.
    @MainActor
    private func expectInLessons(_ studentName: String, qid: String) async throws {
        var settled: SettledLesson?
        let deadline = Date().addingTimeInterval(30)
        repeat {
            settled = SettledLesson(try await backend.fields("questions/\(qid)") ?? [:])
            if settled == nil { pause(seconds: 0.5) }
        } while settled == nil && Date() < deadline
        try require(settled != nil, "the lesson was settled without its length")
        try require(tapWhenHittable(app.buttons["tab_item_lessons"], "the Lessons tab"), "no Lessons tab")
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", studentName)).firstMatch
        try require(row.waitForExistence(timeout: 20), "the lesson with \(studentName) is not in Lessons")
        attach("lessons row", row.label)
        XCTAssertTrue(row.label.contains(settled!.durationText),
                      "the Lessons row does not show the length \(settled!.durationText): \(row.label)")
        XCTAssertGreaterThan(settled!.earningsCents, 0, "the lesson earned the teacher nothing")
        XCTAssertTrue(row.label.contains(settled!.earningsNumberText),
                      "the Lessons row does not show the earnings \(settled!.earningsNumberText): \(row.label)")
    }

    /// IOS-M-07: Earnings shows this month's total, the lesson included —
    /// every lesson this run's teacher has had, as the backend settled them
    /// (the pairs of a run share one teacher).
    @MainActor
    private func expectInEarnings(_ uid: String) async throws {
        var cents = 0
        for qid in try await backend.documentIDs("questions", where: "teacherUid", is: uid) {
            let fields = try await backend.fields("questions/\(qid)") ?? [:]
            guard (fields["status"] as? [String: Any])?["stringValue"] as? String == "completed",
                  let settled = SettledLesson(fields) else { continue }
            cents += settled.earningsCents
        }
        XCTAssertGreaterThan(cents, 0, "the teacher's lessons earned nothing")
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 2
        let expected = formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? ""

        let total = app.staticTexts["earnings_month_total"]
        for _ in 0..<4 where !total.exists {
            try require(tapWhenHittable(app.buttons["tab_item_earnings"], "the Earnings tab"), "no Earnings tab")
            _ = total.waitForExistence(timeout: 10)
        }
        try require(total.exists, "Earnings shows no total for the month")
        let deadline = Date().addingTimeInterval(20)
        while !total.label.contains(expected) && Date() < deadline { pause(seconds: 0.5) }
        attach("earnings", total.label)
        XCTAssertTrue(total.label.contains(expected), "Earnings shows \(total.label) for the month, not \(expected)")
    }

    @MainActor
    private func require(_ condition: Bool, _ message: String) throws {
        guard !condition else { return }
        attach("screen", app?.debugDescription ?? "no app")
        throw Failed(message)
    }

    private struct Failed: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
