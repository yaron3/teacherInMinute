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
//             free again (no busy mark), back on the dashboard
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

    @MainActor
    func testTeachingALessonTheStudentEnds() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["LESSON_TEACHER_EMAIL"], let password = env["LESSON_TEACHER_PASSWORD"],
              let uid = env["LESSON_TEACHER_UID"] else {
            throw XCTSkip("run through scripts/run-lesson-tests.sh, which sets the lesson teacher's account")
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

        // In the lesson: as text, since there is no audio between simulators.
        let end = app.buttons["session_end_button"]
        let textOnly = app.buttons["connection_setup_continue_as_text"]
        let entered = waitForAny([end, textOnly], timeout: 90) { [self] in _ = dismissSystemPromptIfPresent() }
        if entered == textOnly { _ = tapWhenHittable(textOnly, "Continue with text only") }
        try require(end.waitForExistence(timeout: 90), "the teacher never entered the lesson")

        // Until the student ends it.
        let left = waitForDisappearance(end, timeout: 300)
        try require(left, "the lesson never ended for the teacher")

        var busy: Any? = "busy"
        let deadline = Date().addingTimeInterval(30)
        repeat {
            busy = try await backend.value("teachers/\(uid)/busy")
            if busy != nil { pause(seconds: 0.5) }
        } while busy != nil && Date() < deadline
        XCTAssertNil(busy, "the teacher is still marked busy after the lesson")
        // Past whatever summary follows, back on the dashboard.
        let home = waitForAny([app.buttons["availability_toggle"], app.switches["availability_toggle"]], timeout: 60) { [self] in
            for label in ["Done", "סיום", "OK", "אישור"] { _ = tapIfPresent(app.buttons[label]) }
            _ = tapIfPresent(app.buttons["dialog_confirm_button"])
        }
        if home == nil { attach("after the lesson", app.debugDescription) }
        XCTAssertNotNil(home, "the teacher did not get back to the dashboard")
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
