import Foundation
import Testing
@testable import TeacherMinute

/// Whether the other side of a running lesson is still in it: what one side
/// reads of the other's `lessonPresence` entry, and what it makes of it.
struct LessonPresenceTests {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  // MARK: Reading a side

  @Test func aSideWithALiveConnectionIsConnected() {
    let reading = LessonPresenceReading(value: [
      "connections": ["c1": true],
      "lostAt": 1_700_000_000_000.0,
    ] as [String: Any])

    #expect(reading?.isConnected == true)
    // Its old connection's handler fired after it had reconnected.
    #expect(reading?.isLost == false)
  }

  @Test func aSideWithNoConnectionLeftIsLost() {
    let reading = LessonPresenceReading(value: ["lostAt": 1_700_000_000_000.0])

    #expect(reading?.isLost == true)
    #expect(reading?.lostAt == 1_700_000_000_000)
  }

  @Test func leavingIsNotBeingLost() {
    let reading = LessonPresenceReading(value: [
      "lostAt": 1_700_000_000_000.0,
      "leftAt": 1_700_000_005_000.0,
    ])

    #expect(reading?.hasLeft == true)
    #expect(reading?.isLost == false)
  }

  @Test func timesAreReadWhicheverWayTheNumberArrives() {
    let asInt = LessonPresenceReading(value: ["leftAt": 1_700_000_000_000])
    let asNumber = LessonPresenceReading(value: ["leftAt": NSNumber(value: 1_700_000_000_000.0)])

    #expect(asInt?.leftAt == 1_700_000_000_000)
    #expect(asNumber?.leftAt == 1_700_000_000_000)
  }

  @Test func aSideThatPublishedNothingIsNotRead() {
    #expect(LessonPresenceReading(value: nil) == nil)
    #expect(LessonPresenceReading(value: "gone") == nil)
  }

  @Test func bothSidesAreReadByRole() {
    let sides = LessonPresenceReading.sides(from: [
      "student": ["lostAt": 1_700_000_000_000.0],
      "teacher": ["connections": ["c1": true]],
    ] as [String: Any])

    #expect(sides["student"]?.isLost == true)
    #expect(sides["teacher"]?.isConnected == true)
  }

  // MARK: What this side makes of the other one

  @Test func aDroppedConnectionHasTheGracePeriodToComeBack() {
    var tracker = PeerPresenceTracker()
    tracker.receive(LessonPresenceReading(lostAt: 1), at: start)

    #expect(tracker.secondsToReconnect(at: start) == 30)
    #expect(tracker.secondsToReconnect(at: start.addingTimeInterval(10.5)) == 20)
    #expect(!tracker.isGone(at: start.addingTimeInterval(29)))
  }

  @Test func theGracePeriodCountsFromWhenTheDropWasFirstSeen() {
    var tracker = PeerPresenceTracker()
    tracker.receive(LessonPresenceReading(lostAt: 1), at: start)
    // Read again, still cut off: the count does not start over.
    tracker.receive(LessonPresenceReading(lostAt: 1), at: start.addingTimeInterval(10))

    #expect(tracker.secondsToReconnect(at: start.addingTimeInterval(10)) == 20)
  }

  @Test func comingBackInTimeKeepsTheLesson() {
    var tracker = PeerPresenceTracker()
    tracker.receive(LessonPresenceReading(lostAt: 1), at: start)
    tracker.receive(LessonPresenceReading(isConnected: true, lostAt: 1), at: start.addingTimeInterval(12))

    #expect(tracker.secondsToReconnect(at: start.addingTimeInterval(12)) == nil)
    #expect(!tracker.isGone(at: start.addingTimeInterval(60)))
  }

  @Test func stayingAwayPastTheGracePeriodIsGone() {
    var tracker = PeerPresenceTracker()
    tracker.receive(LessonPresenceReading(lostAt: 1), at: start)

    #expect(tracker.secondsToReconnect(at: start.addingTimeInterval(45)) == 0)
    #expect(tracker.isGone(at: start.addingTimeInterval(30)))
  }

  @Test func leavingIsGoneAtOnce() {
    var tracker = PeerPresenceTracker()
    tracker.receive(LessonPresenceReading(isConnected: true, leftAt: 1), at: start)

    #expect(tracker.isGone(at: start))
    #expect(tracker.secondsToReconnect(at: start) == nil)
  }

  @Test func leavingIsFinal() {
    var tracker = PeerPresenceTracker()
    tracker.receive(LessonPresenceReading(leftAt: 1), at: start)
    // The lesson's presence is removed with the lesson.
    tracker.receive(nil, at: start.addingTimeInterval(1))

    #expect(tracker.hasLeft)
    #expect(tracker.isGone(at: start.addingTimeInterval(1)))
  }

  @Test func nothingPublishedIsStillInTheLesson() {
    var tracker = PeerPresenceTracker()
    tracker.receive(nil, at: start)

    #expect(!tracker.isGone(at: start.addingTimeInterval(120)))
    #expect(tracker.secondsToReconnect(at: start) == nil)
  }
}
