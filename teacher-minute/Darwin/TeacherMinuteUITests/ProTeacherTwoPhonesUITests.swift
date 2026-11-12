//
//  ProTeacherTwoPhonesUITests.swift
//  TeacherMinuteUITests
//
//  IOS-E-03: one teacher signed in on two iPhones at once, both online,
//  against the local Firebase emulators. Run as two halves at the same time,
//  one per simulator, by scripts/ui-tests/run_lesson_tests.sh (pair
//  "two-phones"), which creates the teacher and hands both halves the same
//  account. QA test plan:
//
//   IOS-E-03  both phones online leave one online record for the teacher;
//             a question reaches both; both tap Accept at the same moment and
//             exactly one of them enters the lesson, the question accepted
//             once, by this teacher
//
//  The halves meet only through the emulators, at uiTestSync/{SYNC_ID}:
//  each says when it is online, half "a" then seeds the question and names
//  the moment to tap, and each reports what its tap led to.
//
//  Skipped unless the run sets LESSON_TEACHER_EMAIL, LESSON_TEACHER_PASSWORD,
//  LESSON_TEACHER_UID, SYNC_ID and PHONE (a or b).
//

import XCTest

final class ProTeacherTwoPhonesUITests: ProTeacherEmulatorTestCase {

    @MainActor
    func testOneTeacherOnTwoPhones() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["LESSON_TEACHER_EMAIL"], let password = env["LESSON_TEACHER_PASSWORD"],
              let uid = env["LESSON_TEACHER_UID"], let sync = env["SYNC_ID"], let phone = env["PHONE"] else {
            throw XCTSkip("run through scripts/ui-tests/run_lesson_tests.sh <student-udid> <teacher-udid> two-phones")
        }
        guard await backend.isRunning() else { throw XCTSkip("Firebase emulators not running") }
        let base = "uiTestSync/\(sync)"
        addUIInterruptionMonitor(withDescription: "iOS system prompt") { [promptDismissLabels] alert in
            for label in promptDismissLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        // Signed in and online, on this phone.
        launchApp()
        let logIn = app.buttons["welcome_log_in"]
        _ = logIn.waitForExistence(timeout: 30)
        for _ in 0..<4 where !(logIn.exists && logIn.isHittable) { app.swipeUp() }
        openLoginForm()
        submitLogin(email: email, password: password)
        try require(waitForDashboard(timeout: 90), "[\(phone)] signing in did not reach the dashboard")
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 20) { allow.tap() }
        let toggle = app.switches["availability_toggle"]
        var online = false
        for attempt in 0..<40 where !online {
            let listed = try await backend.exists("onlineTeachers/\(uid)")
            online = listed && (toggle.exists ? (toggle.value as? String) == "1" : true)
            if !online {
                if attempt == 10 { _ = tapIfPresent(app.buttons["availability_toggle"]) }
                if allow.exists { allow.tap() }
                pause(seconds: 1)
            }
        }
        try require(online, "[\(phone)] the teacher did not come online on this phone")
        // iOS offers to save the password after the login, in a sheet that
        // would cover the card when it comes.
        let savePassword = app.sheets["Save Password?"]
        if savePassword.waitForExistence(timeout: 10) { _ = tapIfPresent(savePassword.buttons["Not Now"]) }
        _ = tapIfPresent(app.buttons["Not Now"])
        try await backend.put("\(base)/ready/\(phone)", true)

        // Half "a" waits for both, checks the one online record and seeds the
        // question; both then tap at the same moment.
        if phone == "a" {
            let bothReady = try await waitFor(timeout: 240) {
                let a = try await self.backend.exists("\(base)/ready/a")
                let b = try await self.backend.exists("\(base)/ready/b")
                return a && b
            }
            try require(bothReady, "the other phone never came online")
            let records = try await backend.childKeys("onlineTeachers").filter { $0 == uid }
            XCTAssertEqual(records.count, 1, "two phones online left \(records.count) online records")
            let status = try await backend.value("teachers/\(uid)/status") as? String
            XCTAssertEqual(status, "online", "the teacher is not online with both phones signed in")
            let qid = try await seedQuestion(for: uid)
            try await backend.put("\(base)/question", [
                "qid": qid, "goAt": Int(Date().addingTimeInterval(25).timeIntervalSince1970 * 1000),
            ])
        }
        var plan: [String: Any] = [:]
        _ = try await waitFor(timeout: 300) {
            plan = (try await self.backend.value("\(base)/question") as? [String: Any]) ?? [:]
            return plan["qid"] != nil
        }
        let qid = try XCTUnwrap(plan["qid"] as? String, "[\(phone)] no question was seeded")
        let goAt = Date(timeIntervalSince1970: Double((plan["goAt"] as? Int) ?? 0) / 1000)
        currentQid = qid
        let accept = visibleAcceptButton(timeout: 60)
        try require(accept != nil, "[\(phone)] the question's card never showed on this phone")
        currentQid = ""
        let wait = goAt.timeIntervalSinceNow
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        accept?.tap()

        // What the tap led to on this phone.
        let end = app.buttons["session_end_button"]
        let textOnly = app.buttons["connection_setup_continue_as_text"]
        let landed = waitForAny([end, textOnly, dialogButton], timeout: 45) { [self] in _ = dismissSystemPromptIfPresent() }
        let outcome: String
        if landed == end || landed == textOnly {
            outcome = "lesson"
        } else if landed == dialogButton {
            outcome = "refused: \(dialogText())"
        } else {
            outcome = acceptButton.exists ? "card still up" : "card closed"
        }
        attach("outcome on phone \(phone)", outcome)
        try await backend.put("\(base)/result/\(phone)", outcome)

        guard phone == "a" else { return }
        var results: [String: String] = [:]
        _ = try await waitFor(timeout: 120) {
            results = (try await self.backend.value("\(base)/result") as? [String: String]) ?? [:]
            return results.count == 2
        }
        attach("outcomes", "\(results)")
        XCTAssertEqual(results.count, 2, "only \(results.keys.sorted()) reported")
        XCTAssertEqual(results.values.filter { $0 == "lesson" }.count, 1,
                       "the lesson went to \(results.values.filter { $0 == "lesson" }.count) phones: \(results)")
        let question = try await backend.fields("questions/\(qid)") ?? [:]
        XCTAssertEqual((question["acceptedByTeacher"] as? [String: Any])?["stringValue"] as? String, uid,
                       "the question is not accepted by the teacher")

        // Out of the way of later runs: the lesson written off, the teacher off.
        try await backend.merge("questions/\(qid)", ["status": "cancelled"])
        try await backend.delete("questions/\(qid)")
        try await backend.patch("teachers/\(uid)", ["status": "offline"])
        try await backend.delete("onlineTeachers/\(uid)")
    }

    // MARK: - Steps

    /// A question from a fresh student, offered to this teacher alone, as
    /// dispatch leaves it.
    private func seedQuestion(for teacherUid: String) async throws -> String {
        let student = try await backend.createAccount(prefix: "two-phones.student")
        try await backend.merge("users/\(student.uid)", ["role": "student", "fullName": "Two Phones Student", "remainingMinutes": 30])
        let qid = "two-phones-\(UUID().uuidString.prefix(8).lowercased())"
        let now = Date()
        try await backend.merge("questions/\(qid)/invites/\(teacherUid)", [
            "teacherUid": teacherUid, "response": "pending", "wave": 1,
            "invitedAt": now, "expiresAt": now.addingTimeInterval(180),
        ])
        try await backend.merge("questions/\(qid)", [
            "studentUid": student.uid, "status": "searching", "topic": "algebra",
            "text": "Two phones: which one takes it?", "conversationType": "text",
            "dispatchWave": 1, "alreadyInvited": [teacherUid],
            // As seedQuestion in the base class: keeps the emulator's
            // immediate abandoned-lesson check away.
            "joinedParticipants": [student.uid], "lessonId": "\(qid)-lesson",
            "createdAt": now, "updatedAt": now,
        ])
        try await backend.put("teacherInvites/\(teacherUid)/\(qid)", [
            "questionId": qid, "topic": "algebra", "text": "Two phones: which one takes it?",
            "expiresAt": Int(now.addingTimeInterval(180).timeIntervalSince1970 * 1000),
            "wave": 1, "studentId": student.uid, "studentName": "Two Phones Student",
            "conversationType": "text", "pricePerMinuteCents": 50,
        ])
        return qid
    }

    private func waitFor(timeout: TimeInterval, _ condition: @escaping () async throws -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if try await condition() { return true }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } while Date() < deadline
        return false
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
