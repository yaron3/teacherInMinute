import Foundation
import Testing
@testable import TeacherMinute

/// A lesson the teacher left for Settings is kept across launches, for that
/// teacher only, and only while it could still be waiting to start.
struct LessonLeftForSettingsStoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func newTeacherUid() -> String {
        "teacher-\(UUID().uuidString)"
    }

    private func lesson(for teacherUid: String, leftSecondsAgo: Double) -> LessonLeftForSettings {
        let leftAt = now.timeIntervalSince1970 - leftSecondsAgo
        return LessonLeftForSettings(
            questionId: "question-1",
            teacherUid: teacherUid,
            conversationType: "audio",
            studentUid: "student-1",
            studentName: "Dana",
            studentImageURL: "",
            questionText: "What does a standard deviation measure?",
            questionPhotoUrls: ["https://example.com/photo.jpg"],
            pricePerMinuteCents: 150,
            currencyCode: "ILS",
            acceptedAt: (leftAt - 20) * 1000,
            leftAt: leftAt
        )
    }

    @Test func aSavedLessonIsReadBackWhole() {
        let uid = newTeacherUid()
        defer { LessonLeftForSettingsStore.clear(teacherUid: uid) }
        let saved = lesson(for: uid, leftSecondsAgo: 30)

        LessonLeftForSettingsStore.save(saved)

        #expect(LessonLeftForSettingsStore.lesson(teacherUid: uid, now: now) == saved)
    }

    @Test func anotherTeacherSigningInDoesNotGetIt() {
        let uid = newTeacherUid()
        let otherUid = newTeacherUid()
        defer { LessonLeftForSettingsStore.clear(teacherUid: uid) }

        LessonLeftForSettingsStore.save(lesson(for: uid, leftSecondsAgo: 30))

        #expect(LessonLeftForSettingsStore.lesson(teacherUid: otherUid, now: now) == nil)
        #expect(LessonLeftForSettingsStore.lesson(teacherUid: uid, now: now) != nil)
    }

    @Test func anEndedLessonIsForgotten() {
        let uid = newTeacherUid()
        LessonLeftForSettingsStore.save(lesson(for: uid, leftSecondsAgo: 30))

        LessonLeftForSettingsStore.clear(teacherUid: uid)

        #expect(LessonLeftForSettingsStore.lesson(teacherUid: uid, now: now) == nil)
    }

    @Test func oneLeftLongerAgoThanALessonCanWaitIsDropped() {
        let uid = newTeacherUid()
        defer { LessonLeftForSettingsStore.clear(teacherUid: uid) }
        let maxAge = LessonLeftForSettingsStore.maxAgeSeconds

        LessonLeftForSettingsStore.save(lesson(for: uid, leftSecondsAgo: maxAge + 1))

        #expect(LessonLeftForSettingsStore.lesson(teacherUid: uid, now: now) == nil)
        // Dropped, not just passed over: a clock set back does not bring it back.
        #expect(LessonLeftForSettingsStore.lesson(teacherUid: uid, now: now.addingTimeInterval(-maxAge)) == nil)
    }

    @Test func oneStillInsideTheWindowIsKept() {
        let uid = newTeacherUid()
        defer { LessonLeftForSettingsStore.clear(teacherUid: uid) }

        LessonLeftForSettingsStore.save(lesson(for: uid, leftSecondsAgo: LessonLeftForSettingsStore.maxAgeSeconds - 1))

        #expect(LessonLeftForSettingsStore.lesson(teacherUid: uid, now: now) != nil)
    }

    @Test func savingAgainReplacesTheEarlierLesson() {
        let uid = newTeacherUid()
        defer { LessonLeftForSettingsStore.clear(teacherUid: uid) }
        LessonLeftForSettingsStore.save(lesson(for: uid, leftSecondsAgo: 300))
        let later = lesson(for: uid, leftSecondsAgo: 10)

        LessonLeftForSettingsStore.save(later)

        #expect(LessonLeftForSettingsStore.lesson(teacherUid: uid, now: now) == later)
    }
}
