//
//  ProTeacherDispatchUITests.swift
//  TeacherMinuteUITests
//
//  How questions reach Pro Teacher, and leave it, against the real backend on
//  the local Firebase emulators. QA test plan:
//
//   IOS-D-16  the teacher declines: only their own card closes
//   IOS-D-19  the student cancels: the card closes; a late tap is told so
//   IOS-D-10  a question the student asks reaches the online teacher
//   IOS-D-21  a teacher who is in a lesson gets no invite
//   IOS-D-23  a teacher the student blocked gets no invite
//
//  The first two seed a question already sent to both teachers. The last three
//  have the student ask through the real createQuestion, so dispatch itself
//  decides who hears of it; every other teacher on the emulators is taken
//  offline first, so the question can reach only the two the test owns.
//
//  Setup and running are as for ProTeacherAcceptRaceUITests. The emulators must
//  include the backend's emulator-only task scheduling (emulatorSchedule.ts):
//  without it the search timeout fires the moment a question is asked.
//

import XCTest

final class ProTeacherDispatchUITests: ProTeacherEmulatorTestCase {

    /// IOS-D-16: declining closes this teacher's card and nobody else's.
    @MainActor
    func testDecliningClosesOnlyThisTeachersCard() async throws {
        try await signInAsNewTeacher()
        let qid = try await seedQuestion()
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 30), "the invite card never appeared")

        let decline = try XCTUnwrap(visibleCardButton("decline"), "Decline was never tappable")
        decline.tap()
        XCTAssertTrue(waitForDisappearance(acceptButton, timeout: 15), "the card stayed after declining")

        let ownInvite = try await backend.strings("questions/\(qid)/invites/\(appTeacher.uid)")
        XCTAssertEqual(ownInvite?["response"], "decline")
        let otherInvite = try await backend.strings("questions/\(qid)/invites/\(otherTeacher.uid)")
        XCTAssertEqual(otherInvite?["response"], "pending", "the other teacher's invite changed too")
        let otherCard = try await backend.exists("teacherInvites/\(otherTeacher.uid)/\(qid)")
        XCTAssertTrue(otherCard, "the other teacher's card was removed too")
        let status = try await backend.strings("questions/\(qid)")?["status"]
        XCTAssertEqual(status, "searching", "declining ended the search")

        pause(seconds: 2)
        XCTAssertFalse(dialogButton.exists, "declining showed a dialog: \(dialogText())")
    }

    /// IOS-D-19: the student cancels while the card is up.
    @MainActor
    func testStudentCancellingClosesTheCard() async throws {
        try await signInAsNewTeacher()
        let qid = try await seedQuestion()
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 30), "the invite card never appeared")

        let outcome = try await backend.call("cancelQuestion", as: student, data: ["questionId": qid])
        XCTAssertTrue(outcome.succeeded, "cancelQuestion: \(outcome)")

        XCTAssertTrue(waitForDisappearance(acceptButton, timeout: 15), "the card stayed after the student cancelled")
        let otherCard = try await backend.exists("teacherInvites/\(otherTeacher.uid)/\(qid)")
        XCTAssertFalse(otherCard, "the other teacher's card was not removed")
        pause(seconds: 2)
        XCTAssertFalse(dialogButton.exists, "a dialog appeared although the teacher never tapped: \(dialogText())")
    }

    /// IOS-D-19: a tap on a card whose cancellation has not reached the phone
    /// yet is told the student cancelled.
    @MainActor
    func testTappingACardTheStudentCancelledSaysSo() async throws {
        try await signInAsNewTeacher()
        let qid = try await seedQuestion()
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 30), "the invite card never appeared")

        let outcome = try await backend.call("cancelQuestion", as: student, data: ["questionId": qid])
        XCTAssertTrue(outcome.succeeded, "cancelQuestion: \(outcome)")
        XCTAssertTrue(waitForDisappearance(acceptButton, timeout: 15), "the card did not close after the cancel")

        // The removal arriving late, as on a weak network.
        try await backend.put("teacherInvites/\(appTeacher.uid)/\(qid)", card(for: qid))
        let stale = try XCTUnwrap(visibleCardButton("accept", timeout: 15), "the stale card was not shown")
        stale.tap()

        XCTAssertTrue(dialogButton.waitForExistence(timeout: 20), "no dialog after accepting a cancelled question")
        let text = dialogText()
        attach("dialog", text)
        XCTAssertTrue(cancelledMessages.contains { text.contains($0) },
                      "the dialog does not say the student cancelled: \(text)")
        dialogButton.tap()
        XCTAssertTrue(waitForDisappearance(dialogButton, timeout: 5), "the dialog did not close")
        pause(seconds: 3)
        XCTAssertFalse(acceptButton.exists, "the cancelled card came back")
    }

    /// IOS-D-10: a question the student asks reaches the online teacher.
    @MainActor
    func testAQuestionAskedReachesTheOnlineTeacher() async throws {
        try await signInAsNewTeacher()
        try await prepareRealDispatch()
        let qid = try await ask()

        XCTAssertTrue(acceptButton.waitForExistence(timeout: 20), "the asked question never reached the app")
        let otherInvited = try await waitForInvite(of: otherTeacher, to: qid)
        XCTAssertTrue(otherInvited, "the other online teacher was not invited")
        let status = try await backend.strings("questions/\(qid)")?["status"]
        XCTAssertEqual(status, "searching")
    }

    /// IOS-D-21: a teacher who is in a lesson is not invited.
    @MainActor
    func testABusyTeacherGetsNoInvite() async throws {
        try await signInAsNewTeacher()
        try await prepareRealDispatch()
        try await backend.put(
            "teachers/\(appTeacher.uid)/busy",
            ["questionId": "earlier-lesson", "since": Int(Date().timeIntervalSince1970 * 1000)]
        )
        let qid = try await ask()

        let otherInvited = try await waitForInvite(of: otherTeacher, to: qid)
        XCTAssertTrue(otherInvited, "dispatch did not run: the free teacher was not invited either")
        pause(seconds: 5)
        let ownCard = try await backend.exists("teacherInvites/\(appTeacher.uid)/\(qid)")
        XCTAssertFalse(ownCard, "the busy teacher was invited")
        XCTAssertFalse(acceptButton.exists, "the busy teacher's app shows the question")
    }

    /// IOS-D-23: a teacher the student blocked is not invited.
    @MainActor
    func testABlockedTeacherGetsNoInvite() async throws {
        try await signInAsNewTeacher()
        try await prepareRealDispatch()
        // As blockTeacher records it after an earlier lesson.
        try await backend.merge("users/\(student.uid)/blockedTeachers/\(appTeacher.uid)", [
            "teacherUid": appTeacher.uid,
            "teacherName": "Race App Teacher",
            "questionId": "earlier-lesson",
            "blockedAt": Date(),
        ])
        let qid = try await ask()

        let otherInvited = try await waitForInvite(of: otherTeacher, to: qid)
        XCTAssertTrue(otherInvited, "dispatch did not run: the other teacher was not invited either")
        pause(seconds: 5)
        let ownCard = try await backend.exists("teacherInvites/\(appTeacher.uid)/\(qid)")
        XCTAssertFalse(ownCard, "the blocked teacher was invited")
        XCTAssertFalse(acceptButton.exists, "the blocked teacher's app shows the question")
    }
}
