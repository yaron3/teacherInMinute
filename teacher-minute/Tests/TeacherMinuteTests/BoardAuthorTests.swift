import CoreGraphics
import Testing
@testable import TeacherMinute

@MainActor
struct BoardAuthorTests {
    @Test func ownReadsTheRoleLooselyAndFallsBackToTeacher() {
        #expect(BoardAuthor.own(role: "student") == .student)
        #expect(BoardAuthor.own(role: "  Student  ") == .student)
        #expect(BoardAuthor.own(role: "teacher") == .teacher)
        #expect(BoardAuthor.own(role: "") == .teacher)
    }

    /// Both devices derive the colors from `isMine` plus their own role, so the
    /// two sides have to disagree about who is who — that is what makes them
    /// agree about the board.
    @Test func peerIsTheOtherSeat() {
        #expect(BoardAuthor.own(role: "teacher").peer == .student)
        #expect(BoardAuthor.own(role: "student").peer == .teacher)
    }

    @Test func boundingBoxSpansEveryPoint() {
        let box = WhiteboardView.boundingBox(of: [
            BoardPoint(x: 120, y: 400),
            BoardPoint(x: 40, y: 450),
            BoardPoint(x: 90, y: 380)
        ])

        #expect(box == CGRect(x: 40, y: 380, width: 80, height: 70))
    }

    /// A straight horizontal line has no height, which is why `peerFocusRect`
    /// pads the box before comparing areas.
    @Test func boundingBoxOfAFlatStrokeHasNoHeight() {
        let box = WhiteboardView.boundingBox(of: [
            BoardPoint(x: 10, y: 50),
            BoardPoint(x: 90, y: 50)
        ])

        #expect(box?.height == 0)
        #expect(box?.width == 80)
    }

    @Test func boundingBoxOfNothingIsNil() {
        #expect(WhiteboardView.boundingBox(of: []) == nil)
    }
}
