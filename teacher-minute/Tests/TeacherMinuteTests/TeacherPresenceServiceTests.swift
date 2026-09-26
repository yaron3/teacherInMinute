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

    /// A keep-alive re-sends "online", which is what brings back a teacher
    /// the backend took offline while the app was away.
    @Test func keepAliveWritesOnline() {
        var statuses: [String] = []
        let service = TeacherPresenceService(teacherUID: "teacher-test") { status in
            statuses.append(status)
        }

        service.goOnline()
        service.sendKeepAlive()

        #expect(statuses == ["online", "online"])
    }

    /// A tick that outlives going offline must not put the teacher back.
    @Test func keepAliveNeverUndoesGoingOffline() {
        var statuses: [String] = []
        let service = TeacherPresenceService(teacherUID: "teacher-test") { status in
            statuses.append(status)
        }

        service.sendKeepAlive()
        service.goOnline()
        service.goOffline()
        service.sendKeepAlive()

        #expect(statuses == ["online", "offline"])
    }
}
