//
//  ProTeacherAvailabilityUITests.swift
//  TeacherMinuteUITests
//
//  The dashboard's availability switch against the real backend on the local
//  Firebase emulators: what the switch says, what teachers/{uid} says, and what
//  students see in onlineTeachers must always agree. QA test plan:
//
//   IOS-P-01  switching on: status online, listed in onlineTeachers with the
//             teacher's subjects, the card reads Available
//   IOS-P-02  switching off: unlisted, the card reads Not available, and a
//             question asked afterwards sends this teacher nothing
//   IOS-P-07  editing subjects while online (from Profile; the dashboard
//             offers it only offline): onlineTeachers carries the new subjects
//             without switching off and on
//   IOS-P-08  flipping the switch several times: every flip sticks, and the
//             card and the database agree after each one
//
//  A teacher comes online by themselves on signing in, so each test starts
//  online. Start the emulators as for ProTeacherAcceptRaceUITests.
//

import XCTest

final class ProTeacherAvailabilityUITests: ProTeacherEmulatorTestCase {

    /// The card's title, in English then Hebrew.
    private let availableTitles = ["Available", "זמין"]
    private let notAvailableTitles = ["Not available", "לא זמין"]

    private var toggle: XCUIElement {
        app.buttons["availability_toggle"].exists ? app.buttons["availability_toggle"] : app.switches["availability_toggle"]
    }

    /// IOS-P-01 and IOS-P-02: off, then on again.
    @MainActor
    func testSwitchingOffAndOnAgain() async throws {
        try await signInAsNewTeacher()
        try await expectState(online: true, "after signing in")

        try flip()
        try await expectState(online: false, "after switching off")

        try flip()
        try await expectState(online: true, "after switching on again")
        let subjects = try await backend.value("onlineTeachers/\(appTeacher.uid)/subjects") as? [String]
        XCTAssertEqual(subjects, [topic], "onlineTeachers lists the wrong subjects")
    }

    /// IOS-P-02: a teacher who switched off is sent nothing.
    @MainActor
    func testATeacherSwitchedOffGetsNoInvite() async throws {
        try await signInAsNewTeacher()
        try await prepareRealDispatch()
        try flip()
        try await expectState(online: false, "after switching off")

        let qid = try await ask()

        let reachedOther = try await waitForInvite(of: otherTeacher, to: qid)
        XCTAssertTrue(reachedOther, "the question reached nobody, so the test proves nothing")
        let reachedThisTeacher = try await waitForInvite(of: appTeacher, to: qid, timeout: 5)
        XCTAssertFalse(reachedThisTeacher, "a teacher who switched off got the question")
    }

    /// IOS-P-07: new subjects reach students without switching off and on.
    @MainActor
    func testEditingSubjectsWhileOnlineUpdatesTheListing() async throws {
        try await signInAsNewTeacher()
        try await expectState(online: true, "after signing in")

        let added = try addASubject()

        var listed: [String] = []
        let deadline = Date().addingTimeInterval(20)
        repeat {
            listed = try await backend.value("onlineTeachers/\(appTeacher.uid)/subjects") as? [String] ?? []
            if listed.contains(added) { break }
            pause(seconds: 0.5)
        } while Date() < deadline
        let presence = try await backend.value("teachers/\(appTeacher.uid)/subjects") as? [String] ?? []
        XCTAssertTrue(presence.contains(added), "teachers/{uid}/subjects kept the old subjects: \(presence)")
        XCTAssertTrue(listed.contains(added), "onlineTeachers kept the old subjects: \(listed)")
        XCTAssertTrue(listed.contains(topic), "onlineTeachers lost the subject the teacher kept: \(listed)")
        try await expectState(online: true, "after editing subjects")
    }

    /// IOS-P-08: several flips, each one sticking.
    @MainActor
    func testFlippingRepeatedlyAlwaysAgrees() async throws {
        try await signInAsNewTeacher()
        try await expectState(online: true, "after signing in")

        var online = true
        for flipNumber in 1...6 {
            try flip()
            online.toggle()
            try await expectState(online: online, "after flip \(flipNumber)")
        }
    }

    // MARK: - Steps

    @MainActor
    private func flip() throws {
        guard tapWhenHittable(toggle, "the availability switch") else {
            attach("screen", app.debugDescription)
            throw Failed("the availability switch was never tappable")
        }
    }

    /// Waits for the card, teachers/{uid} and onlineTeachers all to say
    /// `online`, then checks they still agree a moment later.
    @MainActor
    private func expectState(online: Bool, _ when: String) async throws {
        let titles = online ? availableTitles : notAvailableTitles
        var status: String?
        var listed = false
        var shown = false
        let deadline = Date().addingTimeInterval(20)
        repeat {
            status = try await backend.value("teachers/\(appTeacher.uid)/status") as? String
            listed = try await backend.exists("onlineTeachers/\(appTeacher.uid)")
            shown = titles.contains { app.staticTexts[$0].exists }
            if (status == "online") == online && listed == online && shown { break }
            pause(seconds: 0.5)
        } while Date() < deadline
        let state = "status=\(status ?? "-") listed=\(listed) card=\(shown ? titles[0] : "other")"
        guard (status == "online") == online, listed == online, shown else {
            attach("screen \(when)", app.debugDescription)
            throw Failed("\(when): expected \(online ? "online" : "offline"), got \(state)")
        }
        // Still so after the writes have settled: no flip-back.
        pause(seconds: 2)
        let settled = try await backend.value("teachers/\(appTeacher.uid)/status") as? String
        let stillListed = try await backend.exists("onlineTeachers/\(appTeacher.uid)")
        guard (settled == "online") == online, stillListed == online, titles.contains(where: { app.staticTexts[$0].exists }) else {
            throw Failed("\(when): flipped back to status=\(settled ?? "-") listed=\(stillListed)")
        }
    }

    /// Opens the subject editor from the Profile tab — the dashboard offers
    /// Edit subjects only while offline — adds one subject and saves, then
    /// goes back home; returns the added subject's key.
    @MainActor
    private func addASubject() throws -> String {
        guard tapWhenHittable(app.buttons["tab_item_profile"], "the Profile tab") else { throw Failed("no Profile tab") }
        let edit = app.buttons["profile_subjects_edit_button"]
        scrollToHittable(edit)
        guard tapWhenHittable(edit, "the subjects card's edit") else { throw Failed("no edit on Profile's subjects card") }
        let save = app.buttons["teacher_subjects_continue"]
        guard save.waitForExistence(timeout: 20) else { throw Failed("the subject editor did not open") }

        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'subject_chip_'"))
        if !chips.firstMatch.waitForExistence(timeout: 5) {
            let area = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'teacher_subject_area_'")).firstMatch
            guard tapWhenHittable(area, "a subject area") else { throw Failed("no subject area to pick") }
        }
        let other = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'subject_chip_' AND identifier != %@", "subject_chip_\(topic)")
        ).firstMatch
        guard other.waitForExistence(timeout: 10) else { throw Failed("no other subject to add") }
        let key = String(other.identifier.dropFirst("subject_chip_".count))
        scrollToHittable(other)
        guard tapWhenHittable(other, "subject \(key)") else { throw Failed("subject \(key) was never tappable") }

        scrollToHittable(save)
        guard tapWhenHittable(save, "Save") else { throw Failed("the editor's save was never tappable") }
        guard waitForDisappearance(save, timeout: 20) else { throw Failed("the subject editor did not close") }
        guard tapWhenHittable(app.buttons["tab_item_home"], "the Home tab") else { throw Failed("no Home tab") }
        attach("added subject", key)
        return key
    }

    @MainActor
    private func scrollToHittable(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }

    private struct Failed: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
