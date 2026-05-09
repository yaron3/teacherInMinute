import Testing
@testable import TeacherMinute

@MainActor
struct TeacherPresenceServiceTests {
    @Test func goOnlineThenGoOfflineWritesExpectedStatuses() {
        var statuses: [String] = []
        let service = TeacherPresenceService(teacherUID: "teacher-test") { status in
            statuses.append(status)
        }

        service.goOnline()
        service.goOffline()

        #expect(statuses == ["online", "offline"])
    }
}
