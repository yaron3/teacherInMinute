import Testing
@testable import TeacherMinute

/// A teacher in a session stays in the student home grid, marked busy, but is
/// not one of the teachers "available now".
@MainActor
struct OnlineTeachersBusyTests {
    private func teacher(_ id: String, busy: Bool = false) -> OnlineTeacher {
        OnlineTeacher(id: id, name: id, subject: "Math", profileImageURL: "", isBusy: busy)
    }

    @Test func busyTeachersAreNotCountedAsAvailable() {
        let viewModel = MockStudentHomeViewModel()
        viewModel.onlineTeachers = [
            teacher("a"), teacher("b"), teacher("c"), teacher("d", busy: true),
        ]

        #expect(
            viewModel.onlineTeachersCountText
                == String(format: LocalizationSupport.localized("%d teachers available now"), 3)
        )
    }

    @Test func oneFreeTeacherBesideBusyOnesReadsSingular() {
        let viewModel = MockStudentHomeViewModel()
        viewModel.onlineTeachers = [teacher("a"), teacher("b", busy: true)]

        #expect(viewModel.onlineTeachersCountText == LocalizationSupport.localized("1 teacher available now"))
    }

    @Test func everyoneBusyReadsAsNoneAvailable() {
        let viewModel = MockStudentHomeViewModel()
        viewModel.onlineTeachers = [teacher("a", busy: true), teacher("b", busy: true)]

        #expect(
            viewModel.onlineTeachersCountText
                == String(format: LocalizationSupport.localized("%d teachers available now"), 0)
        )
    }

    @Test func aTeacherIsFreeUnlessMarkedBusy() {
        let presence = OnlineTeacherPresence(id: "a", subjects: [], displayName: "A", photoUrl: "")
        #expect(presence.isBusy == false)
        #expect(teacher("a").isBusy == false)
    }
}
