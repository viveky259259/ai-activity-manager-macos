import Foundation
import Testing
import ActivityCore
import ActivityCoreTestSupport
@testable import ActivityCapture

@Suite("CaptureCoordinator merges sources")
struct CaptureCoordinatorTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEvent(_ bundleID: String, _ name: String, _ offset: TimeInterval) -> ActivityEvent {
        ActivityEvent(
            timestamp: base.addingTimeInterval(offset),
            source: .frontmost,
            subject: .app(bundleID: bundleID, name: name)
        )
    }

    @Test func mergesEventsFromTwoSources() async {
        let a = FakeCaptureSource(identifier: "A")
        let b = FakeCaptureSource(identifier: "B")
        let coordinator = CaptureCoordinator(sources: [a, b])
        await coordinator.start()

        let collect = Task<[ActivityEvent], Never> {
            var out: [ActivityEvent] = []
            for await event in coordinator.events {
                out.append(event)
                if out.count == 4 { break }
            }
            return out
        }

        a.yield(makeEvent("com.a", "A", 0))
        b.yield(makeEvent("com.b", "B", 1))
        a.yield(makeEvent("com.a", "A", 2))
        b.yield(makeEvent("com.b", "B", 3))

        let collected = await collect.value
        #expect(collected.count == 4)

        let aCount = collected.filter {
            if case .app(let id, _) = $0.subject { return id == "com.a" }
            return false
        }.count
        let bCount = collected.filter {
            if case .app(let id, _) = $0.subject { return id == "com.b" }
            return false
        }.count
        #expect(aCount == 2)
        #expect(bCount == 2)

        await coordinator.stop()
    }

    @Test func preservesOrderFromSingleSource() async {
        let a = FakeCaptureSource(identifier: "A")
        let coordinator = CaptureCoordinator(sources: [a])
        await coordinator.start()

        let collect = Task<[ActivityEvent], Never> {
            var out: [ActivityEvent] = []
            for await event in coordinator.events {
                out.append(event)
                if out.count == 5 { break }
            }
            return out
        }

        for i in 0..<5 {
            a.yield(makeEvent("com.a", "A", Double(i)))
        }

        let collected = await collect.value
        let offsets = collected.map { $0.timestamp.timeIntervalSince(base) }
        #expect(offsets == [0, 1, 2, 3, 4])

        await coordinator.stop()
    }

    @Test func stopTerminatesStream() async {
        let a = FakeCaptureSource(identifier: "A")
        let coordinator = CaptureCoordinator(sources: [a])
        await coordinator.start()

        a.yield(makeEvent("com.a", "A", 0))

        // Give the stream time to deliver, then stop.
        let collect = Task<Int, Never> {
            var count = 0
            for await _ in coordinator.events {
                count += 1
            }
            return count
        }

        // Wait a brief moment for the first event to be consumed
        try? await Task.sleep(nanoseconds: 50_000_000)
        await coordinator.stop()

        let total = await collect.value
        #expect(total >= 1)
        #expect(a.stopCount == 1)
    }

    @Test func failedSourceDoesNotKillCoordinator() async {
        struct Boom: Error {}
        let failing = FakeCaptureSource(identifier: "fail")
        failing.queueStartErrors([Boom(), Boom()]) // fail twice then succeed
        let ok = FakeCaptureSource(identifier: "ok")

        let coordinator = CaptureCoordinator(
            sources: [failing, ok],
            backoffBaseMillis: 1,
            backoffCapMillis: 5
        )
        await coordinator.start()

        // OK source should still deliver events
        let collect = Task<ActivityEvent?, Never> {
            for await event in coordinator.events { return event }
            return nil
        }
        ok.yield(makeEvent("com.ok", "OK", 0))
        let first = await collect.value
        #expect(first != nil)

        // Poll until both source statuses have left `.idle` (the start Tasks
        // update statuses asynchronously). Cap at ~500 ms to stay fast.
        var statuses = coordinator.statuses
        for _ in 0..<100 {
            if statuses["ok"] == .running,
               let s = statuses["fail"], s != .idle {
                break
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
            statuses = coordinator.statuses
        }
        #expect(statuses["ok"] == .running)
        let failStatus = statuses["fail"]
        #expect(failStatus != nil)
        if let s = failStatus {
            switch s {
            case .running, .failed:
                break
            default:
                Issue.record("unexpected failing status: \(s)")
            }
        }

        await coordinator.stop()
    }

    @Test func duplicateIdentifiersAreHandled() async throws {
        let a = FakeCaptureSource(identifier: "same")
        let b = FakeCaptureSource(identifier: "same")
        let coordinator = CaptureCoordinator(sources: [a, b])
        await coordinator.start()
        // start() kicks off async tasks that call source.start(); give them a moment.
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(a.startCount == 1)
        #expect(b.startCount == 1)
        await coordinator.stop()
    }
}
