import Testing
@testable import TeacherMinute

/// The keep-alive only keeps time; what it sends is up to the caller.
@MainActor
struct TeacherKeepAliveTests {
    /// Counts sends. A class rather than a captured `var`, so the send
    /// closure has nothing mutable of the test's to capture.
    @MainActor
    final class Sends {
        var count = 0
    }

    @Test func startingSendsNothingUntilTheFirstTick() {
        let sends = Sends()
        let keepAlive = TeacherKeepAlive { sends.count += 1 }

        keepAlive.start()
        defer { keepAlive.stop() }

        // Going online writes a timestamp of its own.
        #expect(sends.count == 0)
        #expect(keepAlive.isRunning)
    }

    @Test func sendNowSendsOnlyWhileRunning() {
        let sends = Sends()
        let keepAlive = TeacherKeepAlive { sends.count += 1 }

        keepAlive.sendNow()
        #expect(sends.count == 0)

        keepAlive.start()
        keepAlive.sendNow()
        #expect(sends.count == 1)

        keepAlive.stop()
        keepAlive.sendNow()
        #expect(sends.count == 1)
        #expect(!keepAlive.isRunning)
    }

    @Test func ticksKeepComingUntilStopped() async throws {
        let sends = Sends()
        let keepAlive = TeacherKeepAlive(interval: 10_000_000) { sends.count += 1 }

        keepAlive.start()
        var waits = 0
        while sends.count < 3 && waits < 200 {
            try await Task.sleep(nanoseconds: 10_000_000)
            waits += 1
        }
        keepAlive.stop()
        #expect(sends.count >= 3)

        let sentBeforeStop = sends.count
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(sends.count == sentBeforeStop)
    }

    /// A second start must not leave a first loop running that `stop` no
    /// longer reaches.
    @Test func startingTwiceLeavesOneLoopToStop() async throws {
        let sends = Sends()
        let keepAlive = TeacherKeepAlive(interval: 10_000_000) { sends.count += 1 }

        keepAlive.start()
        keepAlive.start()
        keepAlive.stop()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(sends.count == 0)
    }
}
