//
//  StudentAskUITests.swift
//  TeacherMinuteUITests
//
//  A signed-in student asking a question, all the way to Send, against the
//  local Firebase emulators. QA test plan:
//
//   IOS-D-01  text of 10+ characters → Find a teacher: the search screen, a
//             searching question with that text, an invite card for the
//             online teacher; cancelling cancels it
//   IOS-D-02  a photo from the library and no text → a question carrying the
//             photo, on the teacher's card too
//   IOS-D-03  under 10 characters is refused on the phone, with nothing sent;
//             over the 1024-character limit is refused by the backend with a
//             message saying the limit
//   IOS-D-04  under 2 minutes → the "not enough minutes" offer, nothing sent
//   IOS-D-05  over the allowance of lessons a minute → "asking too quickly",
//             nothing sent
//   With ProTeacherLessonUITests on a second simulator, paired by
//   scripts/ui-tests/run_lesson_tests.sh (see "Live lessons" below):
//   IOS-L-03 / R-01 / R-05  the student ends, rates, finds it in history
//   IOS-L-04 / R-02         the teacher ends; the student closes the rating
//   IOS-R-03 / R-04         the student reports and blocks the teacher
//
//  Sending is safe here, and only here: a debug build launched with
//  `-firebaseEmulatorHost` talks to nothing but the emulators, and the only
//  teacher online is one this suite writes into the emulator's database.
//  Start the emulators as for ProTeacherAcceptRaceUITests.
//
//  The home has no topic choice — every question goes out as "any" — so the
//  plan's "no topic" case cannot be reached from the app.
//
//  The rate limit counts lessons a teacher accepted, not questions asked
//  (backend rateLimit.ts), so IOS-D-05 seeds two recent lessons rather than
//  asking three times.
//

import XCTest

final class StudentAskUITests: XCTestCase {

    private let backend = EmulatorBackend()
    private var app: XCUIApplication!
    private var teacherUid: String?

    private let systemPromptHosts = [
        "com.apple.springboard",
        "com.apple.AuthenticationServicesUI",
        "com.apple.Passwords",
        "com.apple.CredentialSharingService",
    ].map { XCUIApplication(bundleIdentifier: $0) }

    // Each in English, then Hebrew (backend/Firebase/remote_config_tim.json).
    private let tooShortMessages = ["Take a photo of it, or write at least 10 characters.", "צלם אותה, או כתוב לפחות 10 תווים."]
    private let tooLongMessages = ["Please shorten it to 1024 characters.", "קצרו אותה ל-1024 תווים."]
    private let tooQuicklyMessages = ["You're asking too quickly.", "שליחת השאלות מהירה מדי."]
    private let couldNotSendTitles = ["Could Not Send Question", "לא ניתן לשלוח את השאלה"]

    private var findTeacher: XCUIElement { app.buttons["find_teacher"] }
    private var questionField: XCUIElement { app.textViews["question_text"] }
    private var searchCancel: XCUIElement { app.buttons["search_details_cancel"] }

    override func setUp() async throws {
        continueAfterFailure = false
        guard await backend.isRunning() else {
            throw XCTSkip("Firebase emulators not running; see ProTeacherAcceptRaceUITests for how to start them")
        }
        await MainActor.run {
            // Asking for an audio lesson asks for the microphone.
            addUIInterruptionMonitor(withDescription: "iOS system prompt") { alert in
                for label in ["Allow", "OK", "Allow Paste"] where alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return true
                }
                return false
            }
        }
    }

    // Synchronous on purpose: an async tearDown that quits the app through
    // `await MainActor.run` hangs the whole run after a failed assertion.
    override func tearDownWithError() throws {
        MainActor.assumeIsolated { app?.terminate() }
        // Nobody stays online on the emulators after the suite. Waited for on a
        // background queue, since XCTest's own waits hold the main thread.
        guard let teacherUid else { return }
        let done = DispatchSemaphore(value: 0)
        let backend = backend
        Task.detached {
            try? await backend.patch("teachers/\(teacherUid)", ["status": "offline"])
            try? await backend.delete("onlineTeachers/\(teacherUid)")
            done.signal()
        }
        _ = done.wait(timeout: .now() + 15)
    }

    // MARK: - Tests

    /// IOS-D-01: a text question goes out, and cancelling takes it back.
    @MainActor
    func testAskingWithTextStartsASearch() async throws {
        let student = try await signedInStudent(minutes: 60)
        try await bringATeacherOnline()
        let text = "What is the derivative of x squared? \(Int.random(in: 1000...9999))"

        try ask(text)
        try require(searchCancel.waitForExistence(timeout: 30), "Find a teacher did not start a search")

        let qid = try await waitForQuestion(of: student.uid)
        let question = try await backend.fields("questions/\(qid)") ?? [:]
        XCTAssertEqual(stringValue(question["text"]), text)
        try require(["searching", "accepted"].contains(stringValue(question["status"]) ?? ""),
                      "the question is \(stringValue(question["status"]) ?? "missing")")
        // Earlier suites may have left other emulator teachers online, so the
        // first wave need not include this suite's teacher: whoever it went to
        // must hold a card.
        let invited = try await invitedTeachers(qid)
        let first = try XCTUnwrap(invited.first, "the question was sent to no teacher")
        let card = try await backend.exists("teacherInvites/\(first)/\(qid)")
        try require(card, "an invited teacher has no card")

        try require(tapWhenHittable(searchCancel, "the search's close button"), "the search could not be closed")
        var status = ""
        for _ in 0..<20 where status != "cancelled" {
            status = stringValue(try await backend.fields("questions/\(qid)")?["status"]) ?? ""
            if status != "cancelled" { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        XCTAssertEqual(status, "cancelled", "closing the search did not cancel the question")
        try require(waitForHome(timeout: 20), "closing the search did not return home")
    }

    /// IOS-D-06, the student's side: a formula keyed in on the algebra pad
    /// goes out in the question, and onto the teacher's card, exactly as
    /// written ($$…$$ around the editor's LaTeX). The teacher's side, the
    /// card drawing it as a formula, is ProTeacherDispatchUITests'
    /// testAFormulaOnACardIsDrawnAsAFormula.
    @MainActor
    func testAFormulaGoesToTheTeacherAsWritten() async throws {
        let student = try await signedInStudent(minutes: 60)
        try await bringATeacherOnline()
        for _ in 0..<4 where !questionField.exists {
            try require(tapWhenHittable(app.buttons["question_home_mode_text"], "the Text tab"), "no Text tab at home")
            _ = questionField.waitForExistence(timeout: 5)
        }
        try require(tapWhenHittable(questionField, "the question field"), "no question field")
        questionField.typeText("Solve")
        try require(tapWhenHittable(app.buttons["keyboard_mode_algebra"], "the algebra pad"), "no algebra pad at home")
        for key in ["7", "+", "3"] {
            let button = app.buttons.matching(NSPredicate(format: "label == %@", key)).firstMatch
            try require(tapWhenHittable(button, "the \(key) key"), "the algebra pad has no \(key) key")
        }
        try require(tapWhenHittable(findTeacher, "Find a teacher"), "Find a teacher was never tappable")
        pause(seconds: 1)
        if !searchCancel.exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap() }
        try require(searchCancel.waitForExistence(timeout: 30), "a question with a formula did not start a search")

        let qid = try await waitForQuestion(of: student.uid)
        let text = stringValue(try await backend.fields("questions/\(qid)")?["text"]) ?? ""
        attach("question text", text)
        XCTAssertTrue(text.hasPrefix("Solve"), "the words were lost: \(text)")
        XCTAssertTrue(text.contains("$$7+3$$"), "the formula did not go out as written: \(text)")
        let invited = try await invitedTeachers(qid)
        let first = try XCTUnwrap(invited.first, "the question was sent to no teacher")
        var cardText = ""
        for _ in 0..<20 where cardText.isEmpty {
            cardText = (try await backend.value("teacherInvites/\(first)/\(qid)/text") as? String) ?? ""
            if cardText.isEmpty { pause(seconds: 0.5) }
        }
        XCTAssertEqual(cardText, text, "the teacher's card carries other text than the question")
        _ = tapWhenHittable(searchCancel, "the search's close button")
    }

    /// IOS-D-02: a photo from the library and no words. A simulator has no
    /// camera, so Attach photo opens the library; the camera itself stays a
    /// manual check. Needs a photo in the simulator's library
    /// (`xcrun simctl addmedia <udid> photo.jpg`).
    @MainActor
    func testAskingWithOnlyAPhotoSendsThePhoto() async throws {
        let student = try await signedInStudent(minutes: 60)
        try await bringATeacherOnline()

        try require(tapWhenHittable(app.buttons["capture_question_photo"], "Attach photo"), "no Attach photo at home")
        let picked = pickFirstLibraryPhoto()
        try require(picked, "no photo could be picked from the library")
        try require(app.buttons["delete_question_photo"].waitForExistence(timeout: 30), "the photo was not attached")
        // Find a teacher is disabled while the photo uploads.
        let uploaded = waitForAny([findTeacher], timeout: 30) { } != nil
        try require(uploaded && waitForEnabled(findTeacher, timeout: 60), "the photo never finished uploading")
        try require(tapWhenHittable(findTeacher, "Find a teacher"), "Find a teacher was never tappable")
        try require(searchCancel.waitForExistence(timeout: 30), "a photo question did not start a search")

        let qid = try await waitForQuestion(of: student.uid)
        let question = try await backend.fields("questions/\(qid)") ?? [:]
        let photos = (((question["photoUrls"] as? [String: Any])?["arrayValue"] as? [String: Any])?["values"]
            as? [[String: Any]])?.compactMap { $0["stringValue"] as? String } ?? []
        XCTAssertEqual(photos.count, 1, "the question carries \(photos.count) photos")
        try require(photos.first?.contains("questionImages%2F\(student.uid)%2F") ?? false,
                      "the photo is not in the student's folder: \(photos)")
        let sentTo = try await invitedTeachers(qid)
        let teacher = try XCTUnwrap(sentTo.first, "the question was sent to no teacher")
        var cardPhotos: [String] = []
        for _ in 0..<20 where cardPhotos.isEmpty {
            cardPhotos = (try await backend.value("teacherInvites/\(teacher)/\(qid)/photoUrls") as? [String]) ?? []
            if cardPhotos.isEmpty { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        XCTAssertEqual(cardPhotos, photos, "the teacher's card does not show the photo")

        try require(tapWhenHittable(searchCancel, "the search's close button"), "the search could not be closed")
    }

    /// Taps the first photo in the system photo picker. The picker is drawn by
    /// another process and shows none of its photos to XCUITest, so the tap
    /// goes by position: the first cell of its grid, below the "Private
    /// Access to Photos" banner. A single-selection picker closes on the tap.
    @MainActor
    private func pickFirstLibraryPhoto() -> Bool {
        pause(seconds: 3) // the picker sliding up
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.165, dy: 0.43)).tap()
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if app.buttons["delete_question_photo"].exists { return true }
            pause(seconds: 0.5)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.isEnabled { return true }
            pause(seconds: 0.5)
        } while Date() < deadline
        return false
    }

    /// IOS-D-03: fewer than 10 characters never leaves the phone.
    @MainActor
    func testAShortQuestionIsRefusedOnThePhone() async throws {
        let student = try await signedInStudent(minutes: 60)
        try await bringATeacherOnline()

        try ask("2+2=?")

        try require(nil != waitForText(tooShortMessages, timeout: 15), "a short question showed no message")
        XCTAssertFalse(searchCancel.exists, "a short question started a search")
        let asked = try await backend.count("questions", where: "studentUid", is: student.uid)
        XCTAssertEqual(asked, 0, "a short question was sent")
    }

    /// IOS-D-03: over the length limit, the backend refuses with the limit.
    @MainActor
    func testATooLongQuestionIsRefusedWithTheLimit() async throws {
        let student = try await signedInStudent(minutes: 60)
        try await bringATeacherOnline()

        try ask(String(repeating: "Long question. ", count: 70)) // 1050 characters

        try require(nil != waitForText(tooLongMessages, timeout: 30), "a long question showed no length message")
        try require(nil != waitForText(couldNotSendTitles, timeout: 1), "the refusal had no title")
        let asked = try await backend.count("questions", where: "studentUid", is: student.uid)
        XCTAssertEqual(asked, 0, "a question over the limit was sent")
    }

    /// IOS-D-04: one minute left is not enough to ask.
    @MainActor
    func testTooFewMinutesOffersMinutesInstead() async throws {
        let student = try await signedInStudent(minutes: 1)
        try await bringATeacherOnline()

        try ask("How do I factor x squared minus nine?")

        try require(app.buttons["not_enough_minutes_primary"].waitForExistence(timeout: 20),
                      "one minute left did not offer minutes")
        XCTAssertFalse(searchCancel.exists, "a student without minutes started a search")
        let asked = try await backend.count("questions", where: "studentUid", is: student.uid)
        XCTAssertEqual(asked, 0, "a student without minutes sent a question")
    }

    /// IOS-D-05: two lessons in the last minute use up the allowance.
    @MainActor
    func testAskingTooQuicklyIsRefusedWithAWait() async throws {
        let student = try await signedInStudent(minutes: 60)
        try await bringATeacherOnline()
        let now = Int(Date().timeIntervalSince1970 * 1000)
        try await backend.merge("rateLimits/\(student.uid)", ["sessionsAt": [now - 20_000, now - 10_000]])

        try ask("How do I factor x squared minus nine?")

        try require(nil != waitForText(tooQuicklyMessages, timeout: 30), "asking too quickly showed no wait")
        let asked = try await backend.count("questions", where: "studentUid", is: student.uid)
        XCTAssertEqual(asked, 0, "a rate-limited question was sent")
    }

    // MARK: - Live lessons
    //
    // The student's halves of a live lesson; the teacher's halves
    // (ProTeacherLessonUITests) run on a second simulator at the same time.
    // scripts/ui-tests/run_lesson_tests.sh pairs them and sets
    // LESSON_TEACHER_UID; each is skipped otherwise. Every lesson runs as text:
    // there is no audio between simulators.

    /// IOS-L-03, IOS-R-01, IOS-R-05 — pairs with
    /// testTeachingALessonTheStudentEnds. The student ends the lesson
    /// (completed, a minute charged, the teacher free), rates 4 stars with a
    /// comment, and finds the lesson in their history.
    @MainActor
    func testTakingALessonThenEndingAndRatingIt() async throws {
        let (teacher, student, qid) = try await joinALesson()
        try await chatAndSeeTheBoard(qid)
        try endTheLesson()

        let star = app.buttons["rate_session_star_4"]
        try require(star.waitForExistence(timeout: 60), "ending the lesson showed no rating")
        star.tap()
        let comment = app.textViews["rate_session_comment"]
        try require(tapWhenHittable(comment, "the comment box"), "no comment box after picking stars")
        comment.typeText("Clear and patient.")
        dismissKeyboard()
        try require(tapWhenHittable(app.buttons["rate_session_send"], "Send"), "Send was never tappable")

        try await expectTheLessonOver(qid, teacher: teacher)
        let left = Int(((try await backend.fields("users/\(student.uid)")?["remainingMinutes"]) as? [String: Any])?["integerValue"] as? String ?? "")
        attach("minutes left", "\(left.map(String.init) ?? "none") of 60")
        XCTAssertLessThan(left ?? 60, 60, "a lesson of about 35 seconds charged nothing")

        var rating: [String: Any] = [:]
        for _ in 0..<60 where rating.isEmpty {
            rating = try await backend.fields("teachers/\(teacher)/ratings/\(qid)") ?? [:]
            if rating.isEmpty { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        XCTAssertEqual((rating["studentRate"] as? [String: Any])?["integerValue"] as? String, "4", "the rating was not saved: \(rating)")
        XCTAssertEqual(stringValue(rating["studentComment"]), "Clear and patient.")

        try await expectInHistory("Lesson Teacher", qid: qid)
    }

    /// IOS-L-04, IOS-R-02 — pairs with testTeachingALessonAndEndingIt. The
    /// teacher ends the lesson; the student is offered the rating, closes it
    /// unrated, and the lesson is over and in their history all the same.
    @MainActor
    func testTakingALessonTheTeacherEndsThenSkippingTheRating() async throws {
        let (teacher, _, qid) = try await joinALesson()
        // The teacher's half ends it after 35 seconds. The rating comes up
        // over the lesson screen, whose End stays in the hierarchy beneath it,
        // so the rating itself is what shows the end arrived.
        let close = app.buttons["rate_session_close"]
        try require(close.waitForExistence(timeout: 180), "the teacher's ending never reached the student")
        try require(tapWhenHittable(close, "the rating's close"), "the rating could not be closed")
        try require(waitForHome(timeout: 30), "closing the rating did not return home")

        try await expectTheLessonOver(qid, teacher: teacher)
        let rating = try await backend.fields("teachers/\(teacher)/ratings/\(qid)")
        XCTAssertNil(rating, "closing the rating saved one")
        try await expectInHistory("Lesson Teacher", qid: qid)
    }

    /// IOS-L-05 — pairs with ProTeacherLessonUITests'
    /// testTeachingUntilTheStudentRunsOut. A student with 2 minutes stays in:
    /// a warning comes in the last minute; at nothing left the lesson holds,
    /// offering more minutes or the end; ending from there, after a while on
    /// hold, closes it with exactly the 2 minutes charged.
    @MainActor
    func testRunningOutOfMinutesHoldsThenEndsTheLesson() async throws {
        let (teacher, student, qid) = try await joinALesson(minutes: 2)
        let warning = app.staticTexts["session_banner_minutes_running_out"]
        try require(warning.waitForExistence(timeout: 150), "no warning came before the minutes ran out")
        attach("warning", warning.label)

        let endCall = app.buttons["chat_end_call_farewell"]
        let held = app.buttons["chat_end_prompt_primary"]
        try require(endCall.waitForExistence(timeout: 120), "running out of minutes did not hold the lesson")
        attach("held", "\(held.label) / \(endCall.label)")
        XCTAssertTrue(app.buttons["session_end_button"].exists, "the lesson ended instead of holding")
        // Held a while: the minutes are charged when the lesson is settled,
        // and the hold itself must add nothing (checked at the end).
        pause(seconds: 20)

        try require(tapWhenHittable(endCall, "End the call"), "the hold offered no way to end")
        try require(tapWhenHittable(app.buttons["chat_end_prompt_primary"], "Send and end"), "ending from the hold asked nothing")
        let close = app.buttons["rate_session_close"]
        if close.waitForExistence(timeout: 30) { close.tap() }
        try await expectTheLessonOver(qid, teacher: teacher)
        let left = Int(((try await backend.fields("users/\(student.uid)")?["remainingMinutes"]) as? [String: Any])?["integerValue"] as? String ?? "")
        XCTAssertEqual(left ?? -1, 0, "a 2-minute student ended with \(left.map(String.init) ?? "none") minutes")
    }

    /// IOS-L-06 — pairs with ProTeacherLessonUITests'
    /// testWaitingForAStudentWhoNeverJoins. The teacher takes the question and
    /// the student's app is gone that moment (swiped away before connecting):
    /// the backend's abandoned-lesson check closes the lesson, and the student
    /// is not billed.
    @MainActor
    func testLeavingRightAfterTheAcceptIsNotBilled() async throws {
        let (_, student, qid) = try await askForATextLesson(minutes: 60)
        var status = ""
        for _ in 0..<600 where !["accepted", "in_progress"].contains(status) {
            status = stringValue(try await backend.fields("questions/\(qid)")?["status"]) ?? ""
            if !["accepted", "in_progress"].contains(status) { try await Task.sleep(nanoseconds: 200_000_000) }
        }
        try require(["accepted", "in_progress"].contains(status), "the teacher's half never took the question (\(status))")
        app.terminate()

        // Within the 2-minute grace, or the 5-minute check for a lesson that
        // never started if the app had joined before it went.
        var question: [String: Any] = [:]
        let deadline = Date().addingTimeInterval(400)
        repeat {
            question = try await backend.fields("questions/\(qid)") ?? [:]
            if stringValue(question["status"]) != "cancelled" { try await Task.sleep(nanoseconds: 2_000_000_000) }
        } while stringValue(question["status"]) != "cancelled" && Date() < deadline
        attach("closed", "status=\(stringValue(question["status"]) ?? "") endedBy=\(stringValue(question["endedBy"]) ?? "") reason=\(stringValue(question["endedReason"]) ?? "")")
        XCTAssertEqual(stringValue(question["status"]), "cancelled", "the lesson nobody joined was never closed")
        XCTAssertEqual(stringValue(question["endedBy"]), "system")
        let billed = (question["billedSeconds"] as? [String: Any])?["integerValue"] as? String
        XCTAssertEqual(billed, "0", "a lesson the student never joined was billed")
        let left = Int(((try await backend.fields("users/\(student.uid)")?["remainingMinutes"]) as? [String: Any])?["integerValue"] as? String ?? "")
        XCTAssertEqual(left, 60, "the student was charged for a lesson never joined")
    }

    /// IOS-L-07 — pairs with ProTeacherLessonUITests'
    /// testTheStudentDropsOutAndDoesNotReturn. About 40 s into the lesson the
    /// student's app is gone (as a lost connection): the teacher sees it
    /// reconnecting, and when it does not come back the lesson ends, billed
    /// for the time talked only.
    @MainActor
    func testDroppingOutMidLessonBillsOnlyTheTimeTalked() async throws {
        let (_, student, qid) = try await joinALesson()
        pause(seconds: 40)
        app.terminate()

        var question: [String: Any] = [:]
        let deadline = Date().addingTimeInterval(180)
        repeat {
            question = try await backend.fields("questions/\(qid)") ?? [:]
            if stringValue(question["status"]) != "completed" { try await Task.sleep(nanoseconds: 2_000_000_000) }
        } while stringValue(question["status"]) != "completed" && Date() < deadline
        let seconds = Int((question["lessonSeconds"] as? [String: Any])?["integerValue"] as? String ?? "") ?? -1
        attach("ended", "status=\(stringValue(question["status"]) ?? "") endedBy=\(stringValue(question["endedBy"]) ?? "") lessonSeconds=\(seconds)")
        XCTAssertEqual(stringValue(question["status"]), "completed", "the lesson did not end after the student dropped out")
        // About 40 s talked; not the 30 s of grace after it, nor the wait.
        XCTAssertTrue((30...65).contains(seconds), "the lesson was billed \(seconds) s for about 40 s talked")
        let left = Int(((try await backend.fields("users/\(student.uid)")?["remainingMinutes"]) as? [String: Any])?["integerValue"] as? String ?? "")
        let expected = 60 - (seconds < 30 ? 0 : max(1, seconds / 60 + (seconds % 60 > 30 ? 1 : 0)))
        XCTAssertEqual(left, expected, "charged otherwise than for the time talked")
    }

    /// IOS-R-03, IOS-R-04 — pairs with testTeachingALessonTheStudentEnds. From
    /// the rating screen the student reports the teacher, blocking them too:
    /// the report is stored and the teacher is on their blocked list. Then
    /// Settings → Privacy Controls lists them, and unblocking there lifts it.
    @MainActor
    func testEndingALessonThenReportingAndBlockingTheTeacher() async throws {
        let (teacher, student, qid) = try await joinALesson()
        try endTheLesson()

        try require(tapWhenHittable(app.buttons["rating_report_teacher"], "Report"), "the rating screen offers no report")
        try require(tapWhenHittable(app.buttons["report_reason_not_teaching"], "a reason"), "the report offers no reasons")
        // "Also block" starts ticked (ReportTeacherViewModel.alsoBlock), so it
        // is left as it is.
        try require(app.descendants(matching: .any)["report_also_block"].waitForExistence(timeout: 10), "the report offers no block")
        // The details last: the form has no way to close the keyboard, so
        // Send is scrolled up above it.
        let details = app.textViews["report_details"].exists ? app.textViews["report_details"] : app.textFields["report_details"]
        if details.waitForExistence(timeout: 5) {
            _ = tapWhenHittable(details, "the details box")
            details.typeText("Did not explain anything.")
        }
        let send = app.buttons["report_send"]
        for _ in 0..<3 where !(send.exists && send.isHittable) { app.swipeUp() }
        try require(tapWhenHittable(send, "Send report"), "the report could not be sent")
        try require(tapWhenHittable(app.buttons["report_done"], "Done"), "sending the report showed no confirmation")

        var reported = false
        var blocked = false
        let deadline = Date().addingTimeInterval(30)
        repeat {
            let reports = try await backend.documentIDs("reports", where: "reporterUid", is: student.uid)
            for id in reports where !reported {
                let fields = try await backend.fields("reports/\(id)") ?? [:]
                reported = stringValue(fields["reportedUid"]) == teacher && stringValue(fields["questionId"]) == qid
            }
            blocked = try await backend.fields("users/\(student.uid)/blockedTeachers/\(teacher)") != nil
            if !(reported && blocked) { try await Task.sleep(nanoseconds: 500_000_000) }
        } while !(reported && blocked) && Date() < deadline
        XCTAssertTrue(reported, "the report was not stored")
        try require(blocked, "the teacher is not on the student's blocked list")

        // IOS-R-04's other half: the block shows in Settings → Privacy
        // Controls, and unblocking there lifts it.
        try require(waitForHome(timeout: 30), "not back home after the report")
        try require(tapWhenHittable(app.buttons["side_menu_button"], "the menu"), "no menu button")
        try require(tapWhenHittable(app.buttons["side_menu_item_settings"], "Settings"), "no Settings in the menu")
        // A tap while the menu is still closing does not open the row, so it
        // is tapped until the page comes up.
        let privacy = app.buttons["settings_row_privacyControls"]
        let unblock = app.buttons["unblock_teacher_\(teacher)"]
        for _ in 0..<3 where !unblock.exists {
            if privacy.exists && privacy.isHittable { privacy.tap() }
            _ = unblock.waitForExistence(timeout: 10)
        }
        for _ in 0..<3 where !(unblock.exists && unblock.isHittable) { app.swipeUp() }
        try require(unblock.exists, "the blocked teacher is not listed in Privacy Controls")
        try require(app.staticTexts["Lesson Teacher"].exists, "the blocked teacher is listed without their name")
        try require(tapWhenHittable(unblock, "Unblock"), "Unblock could not be tapped")
        try require(waitForDisappearance(unblock, timeout: 20), "the teacher stayed listed after unblocking")
        var stillBlocked = true
        let lifted = Date().addingTimeInterval(20)
        repeat {
            stillBlocked = try await backend.fields("users/\(student.uid)/blockedTeachers/\(teacher)") != nil
            if stillBlocked { try await Task.sleep(nanoseconds: 500_000_000) }
        } while stillBlocked && Date() < lifted
        XCTAssertFalse(stillBlocked, "unblocking left the teacher on the blocked list")
    }

    /// IOS-L-02, the student's side: the teacher's message arrives, the
    /// answer goes back below it, and the teacher's stroke reaches the board.
    @MainActor
    private func chatAndSeeTheBoard(_ qid: String) async throws {
        _ = tapIfPresent(app.buttons["session_tab_chat"])
        let theirs = app.staticTexts["Let's start with the x terms."]
        try require(theirs.waitForExistence(timeout: 120), "the teacher's message never reached the student")
        let field = app.textFields["chat_message_field"]
        try require(tapWhenHittable(field, "the message field"), "no message field in the lesson")
        let reply = "OK, I moved them to one side."
        field.typeText(reply)
        try require(tapWhenHittable(app.buttons["chat_send_button"], "Send"), "the reply could not be sent")
        dismissKeyboard()
        let mine = app.staticTexts[reply]
        try require(mine.waitForExistence(timeout: 20), "the reply is not in the student's chat")
        XCTAssertLessThan(theirs.frame.minY, mine.frame.minY, "the messages are out of order")

        var strokes: [String] = []
        for _ in 0..<120 where strokes.isEmpty {
            strokes = try await backend.childKeys("questions/\(qid)/board/strokes")
            if strokes.isEmpty { pause(seconds: 0.5) }
        }
        XCTAssertFalse(strokes.isEmpty, "the teacher's stroke never reached the student's board")
    }

    /// A signed-in student who asks; the teacher's half takes it; returns once
    /// the student is in the text lesson.
    @MainActor
    private func askForATextLesson(minutes: Int) async throws -> (teacher: String, student: EmulatorBackend.Account, qid: String) {
        guard let teacher = ProcessInfo.processInfo.environment["LESSON_TEACHER_UID"] else {
            throw XCTSkip("run through scripts/ui-tests/run_lesson_tests.sh, which starts the teacher's half too")
        }
        let student = try await signedInStudent(minutes: minutes)

        // The teacher's half signs in meanwhile. Once it is online, it is made
        // the only teacher online (on the emulators), so the question reaches it.
        var listed = false
        let online = Date().addingTimeInterval(240)
        repeat {
            listed = try await backend.exists("onlineTeachers/\(teacher)")
            if !listed { pause(seconds: 1) }
        } while !listed && Date() < online
        try require(listed, "the teacher's half never came online")
        for uid in try await backend.childKeys("teachers") where uid != teacher {
            try await backend.patch("teachers/\(uid)", ["status": "offline"])
        }

        try ask("Help me with quadratic equations, please")
        try require(searchCancel.waitForExistence(timeout: 30), "Find a teacher did not start a search")
        let qid = try await waitForQuestion(of: student.uid)
        attach("question", qid)

        // A text lesson, chosen on the search screen's last step. The
        // teacher's half waits for this choice before it accepts.
        let text = app.buttons["search_choice_text"]
        for _ in 0..<4 where !text.exists {
            try require(tapWhenHittable(app.buttons["search_details_next"], "Next"), "the search screen has no Next")
            _ = text.waitForExistence(timeout: 3)
        }
        try require(tapWhenHittable(text, "Text"), "the search screen offers no text lesson")
        var chosen = ""
        for _ in 0..<30 where chosen != "text" {
            chosen = stringValue(try await backend.fields("questions/\(qid)")?["conversationType"]) ?? ""
            if chosen != "text" { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        try require(chosen == "text", "choosing text did not reach the question (\(chosen))")
        return (teacher, student, qid)
    }

    /// As far as a text lesson asked for and the teacher's half about to take
    /// it; then into the lesson.
    @MainActor
    private func joinALesson(minutes: Int = 60) async throws -> (teacher: String, student: EmulatorBackend.Account, qid: String) {
        let (teacher, student, qid) = try await askForATextLesson(minutes: minutes)
        let end = app.buttons["session_end_button"]
        let textOnly = app.buttons["connection_setup_continue_as_text"]
        let entered = waitForAny([end, textOnly], timeout: 300)
        if entered == textOnly { try require(tapWhenHittable(textOnly, "Continue with text only"), "text only was never tappable") }
        try require(end.waitForExistence(timeout: 120), "the student never entered the lesson")
        return (teacher, student, qid)
    }

    /// Ends the lesson after 35 seconds: the rating is offered only after 30
    /// or more (ChatSessionView.closeWithOptionalRating).
    @MainActor
    private func endTheLesson() throws {
        pause(seconds: 35)
        try require(tapWhenHittable(app.buttons["session_end_button"], "End"), "End was never tappable")
        try require(tapWhenHittable(app.buttons["chat_end_prompt_primary"], "the end confirmation"), "ending asked nothing")
        // With something on the board, ending first offers to save it.
        let chatOnly = app.buttons["Save to chat only"]
        if chatOnly.waitForExistence(timeout: 5) { chatOnly.tap() }
    }

    /// The question completed and the teacher free.
    private func expectTheLessonOver(_ qid: String, teacher: String) async throws {
        var status = ""
        var busy: Any? = "busy"
        let deadline = Date().addingTimeInterval(60)
        repeat {
            status = stringValue(try await backend.fields("questions/\(qid)")?["status"]) ?? ""
            busy = try await backend.value("teachers/\(teacher)/busy")
            if !(status == "completed" && busy == nil) { try await Task.sleep(nanoseconds: 500_000_000) }
        } while !(status == "completed" && busy == nil) && Date() < deadline
        XCTAssertEqual(status, "completed", "the question did not end")
        XCTAssertNil(busy, "the teacher is still busy after the lesson ended")
    }

    /// IOS-R-05, the student's side: the lesson in the menu's Activity, by
    /// the teacher's name, with the minutes it was charged; its detail shows
    /// the length the backend settled it at.
    @MainActor
    private func expectInHistory(_ teacherName: String, qid: String) async throws {
        let settled = SettledLesson(try await backend.fields("questions/\(qid)") ?? [:])
        try require(settled != nil, "the lesson was settled without its length")
        try require(waitForHome(timeout: 30), "not back home after the lesson")
        try require(tapWhenHittable(app.buttons["side_menu_button"], "the menu"), "no menu button")
        try require(tapWhenHittable(app.buttons["side_menu_item_activity"], "Activity"), "no Activity in the menu")
        let row = app.buttons["activity_lesson_\(qid)"]
        try require(row.waitForExistence(timeout: 20), "the lesson is not in the history")
        attach("history row", row.label)
        XCTAssertTrue(row.label.contains(teacherName), "the history row does not name \(teacherName): \(row.label)")
        XCTAssertTrue(row.label.contains(settled!.billedMinutesText),
                      "the history row does not show the \(settled!.billedMinutesText) charged: \(row.label)")
        try require(tapWhenHittable(row, "the lesson"), "the lesson could not be opened")
        let duration = app.staticTexts[settled!.durationText]
        XCTAssertTrue(duration.waitForExistence(timeout: 10),
                      "the lesson's detail does not show its length \(settled!.durationText)")
    }

    // MARK: - Steps

    /// A student account with `minutes`, signed in through the guest's menu.
    @MainActor
    private func signedInStudent(minutes: Int) async throws -> EmulatorBackend.Account {
        let student = try await backend.createAccount(prefix: "ask.student")
        try await backend.merge(
            "users/\(student.uid)",
            ["role": "student", "fullName": "Asking Student", "remainingMinutes": minutes, "totalMinutes": minutes]
        )
        app = XCUIApplication()
        app.launchArguments = [
            "-firebaseEmulatorHost", EmulatorBackend.host,
            "-firebaseEmulatorSignOut", "YES",
            "-tutorial.student.hidden", "YES",
        ]
        app.launch()

        let start = app.buttons["student_intro_start"]
        try require(tapWhenHittable(start, "the intro's Start", timeout: 60), "the intro's Start never appeared")
        // Right after launch the intro can swallow the first tap.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, start.exists {
            pause(seconds: 3)
            _ = tapIfPresent(start)
        }
        try require(waitForHome(timeout: 60), "Start did not reach home")

        try require(tapWhenHittable(app.buttons["side_menu_button"], "the menu button"), "no menu button")
        try require(tapWhenHittable(app.buttons["side_menu_log_in"], "the menu's Log in"), "no Log in in a guest's menu")
        let emailField = app.textFields["email_input"]
        try require(emailField.waitForExistence(timeout: 20), "the login form did not open")
        try type(student.email, into: emailField, "the login email field")
        try type(student.password, into: app.secureTextFields["password_input"], "the login password field")
        dismissKeyboard()
        let submit = app.buttons["login_submit"]
        try require(tapWhenHittable(submit, "Log in"), "Log in was never tappable")
        // The guest's home is still underneath until the login screen closes.
        let closed = Date().addingTimeInterval(60)
        while submit.exists && Date() < closed { pause(seconds: 0.5) }
        try require(!submit.exists, "the login screen never closed")
        try require(waitForHome(timeout: 90), "logging in did not reach home")
        return student
    }

    /// One teacher online on the emulators, so the app has someone to ask.
    private func bringATeacherOnline() async throws {
        let uid = "ask-teacher-\(Int(Date().timeIntervalSince1970 * 1000))"
        teacherUid = uid
        try await backend.merge("users/\(uid)", ["role": "teacher", "fullName": "Emulator Teacher"])
        try await backend.put("teachers/\(uid)", [
            "status": "offline", "subjects": ["algebra", "calculus"], "displayName": "Emulator Teacher",
        ])
        try await backend.patch("teachers/\(uid)", [
            "status": "online", "lastSeenAt": Int(Date().timeIntervalSince1970 * 1000),
        ])
        var listed = false
        for _ in 0..<30 where !listed {
            listed = try await backend.exists("onlineTeachers/\(uid)")
            if !listed { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        if !listed { throw StepFailed("the emulator teacher was never listed online") }
    }

    /// Opens the text tab, writes `text` and taps Find a teacher.
    @MainActor
    private func ask(_ text: String) throws {
        // A tap on the Text tab can miss while home is still settling: tapped
        // again until the question field shows.
        for _ in 0..<4 where !questionField.exists {
            try require(tapWhenHittable(app.buttons["question_home_mode_text"], "the Text tab"), "no Text tab at home")
            _ = questionField.waitForExistence(timeout: 5)
        }
        try require(tapWhenHittable(questionField, "the question field"), "no question field")
        questionField.typeText(text)
        dismissKeyboard()
        try require(tapWhenHittable(findTeacher, "Find a teacher"), "Find a teacher was never tappable")
        // Tapping the app again lets the interruption monitor answer a
        // microphone prompt, if one came up.
        pause(seconds: 1)
        if !searchCancel.exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap() }
    }

    /// Who the question was sent to, once dispatch has sent it.
    private func invitedTeachers(_ qid: String) async throws -> [String] {
        for _ in 0..<20 {
            let field = try await backend.fields("questions/\(qid)")?["alreadyInvited"] as? [String: Any]
            let invited = ((field?["arrayValue"] as? [String: Any])?["values"] as? [[String: Any]])?
                .compactMap { $0["stringValue"] as? String } ?? []
            if !invited.isEmpty { return invited }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        return []
    }

    private func waitForQuestion(of studentUid: String) async throws -> String {
        for _ in 0..<40 {
            let ids = try await backend.documentIDs("questions", where: "studentUid", is: studentUid)
            if let qid = ids.first { return qid }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw StepFailed("no question was created")
    }

    @MainActor
    private func waitForHome(timeout: TimeInterval) -> Bool {
        let textTab = app.buttons["question_home_mode_text"]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            // Whatever a signed-in student may be shown first.
            _ = tapIfPresent(app.buttons["permissions_setup_skip"])
            _ = tapIfPresent(app.buttons["student_tutorial_skip"])
            _ = tapIfPresent(app.buttons["verify_email_not_now"])
            // After a first lesson the app explains notifications ("Stay in
            // the loop") over home.
            _ = tapIfPresent(app.buttons["Not now"])
            closeSavePasswordSheet()
            if textTab.exists && textTab.isHittable && !app.textFields["email_input"].exists { return true }
            pause(seconds: 0.5)
        } while Date() < deadline
        return false
    }

    /// The first of `texts` to appear anywhere on screen.
    @MainActor
    private func waitForText(_ texts: [String], timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let screen = app.debugDescription
            if let found = texts.first(where: { screen.contains($0) }) { return found }
            pause(seconds: 0.5)
        } while Date() < deadline
        attach("screen", app.debugDescription)
        return nil
    }

    // MARK: - Typing and tapping

    @MainActor
    private func type(_ text: String, into field: XCUIElement, _ described: String) throws {
        try require(field.waitForExistence(timeout: 20), "no \(described)")
        try require(tapWhenHittable(field, described), "\(described) was never tappable")
        _ = closeStrongPasswordSheet(wait: 0.5)
        field.typeText(text)
    }

    @MainActor
    private func closeStrongPasswordSheet(wait: TimeInterval) -> Bool {
        let hosts = (systemPromptHosts + [app!]).filter { $0.state != .notRunning }
        let deadline = Date().addingTimeInterval(wait)
        repeat {
            for host in hosts {
                for label in ["xmark", "Close", "Not Now"] {
                    let button = host.buttons[label]
                    if button.exists && button.isHittable {
                        button.tap()
                        pause(seconds: 0.5)
                        return true
                    }
                }
            }
            pause(seconds: 0.25)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        let deadline = Date().addingTimeInterval(3)
        while app.keyboards.firstMatch.exists && Date() < deadline { pause(seconds: 0.3) }
    }

    @MainActor
    private func tapWhenHittable(_ element: XCUIElement, _ described: String, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            closeSavePasswordSheet()
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
            pause(seconds: 0.5)
        } while Date() < deadline
        return false
    }

    /// iOS offers to save the password just used to log in, a moment after
    /// home appears, and the sheet covers it.
    @MainActor
    private func closeSavePasswordSheet() {
        let sheet = app.sheets["Save Password?"]
        guard sheet.exists else { return }
        let notNow = sheet.buttons["Not Now"]
        if notNow.exists { notNow.tap() } else { _ = tapIfPresent(app.buttons["Not Now"]) }
        pause(seconds: 0.5)
    }

    @MainActor
    private func tapIfPresent(_ element: XCUIElement) -> Bool {
        guard element.exists && element.isHittable else { return false }
        element.tap()
        return true
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline { pause(seconds: 0.5) }
        return !element.exists
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval, whileWaiting: () -> Void = {}) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let found = elements.first(where: \.exists) { return found }
            whileWaiting()
            pause(seconds: 0.5)
        } while Date() < deadline
        return nil
    }

    private func pause(seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [expectation(description: "poll")], timeout: seconds)
    }

    private func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Fails the test with `message` and a picture of the screen, ending it.
    @MainActor
    private func require(_ condition: Bool, _ message: String) throws {
        guard !condition else { return }
        attach("screen", app?.debugDescription ?? "no app")
        if let app {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "screenshot"
            shot.lifetime = .keepAlways
            add(shot)
        }
        throw StepFailed(message)
    }

    private struct StepFailed: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private func stringValue(_ field: Any?) -> String? { (field as? [String: Any])?["stringValue"] as? String }
}
