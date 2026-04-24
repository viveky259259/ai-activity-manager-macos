import Foundation
import Testing
import os
import ActivityCore
import ActivityCoreTestSupport
@testable import ActivityCapture

@Suite("IdleSource polls and emits idle events")
struct IdleSourceTests {
    @Test func scriptedSamples_produceBeginAndEnd() async throws {
        let clock = FakeClock()
        let script = OSAllocatedUnfairLock(initialState: [TimeInterval]([5, 10, 130, 140, 2]))

        let sampler: @Sendable () -> TimeInterval = {
            script.withLock { s in
                guard !s.isEmpty else { return 0 }
                return s.removeFirst()
            }
        }

        let source = IdleSource(
            clock: clock,
            threshold: 120,
            pollInterval: 0.01,
            sampler: sampler
        )
        try await source.start()

        let task = Task<[ActivityEvent], Never> {
            var out: [ActivityEvent] = []
            for await event in source.events {
                out.append(event)
                if out.count == 2 { break }
            }
            return out
        }

        let events = await task.value
        await source.stop()

        #expect(events.count == 2)
        #expect(events.map { $0.attributes["idleTransition"] } == ["begin", "end"])
        #expect(events.allSatisfy { $0.source == .idle })
    }

    @Test func sustainedActivity_producesNoEvents() async throws {
        let clock = FakeClock()
        // Always return values well below threshold.
        let sampler: @Sendable () -> TimeInterval = { 5 }

        let source = IdleSource(
            clock: clock,
            threshold: 120,
            pollInterval: 0.005,
            sampler: sampler
        )
        try await source.start()

        // Let the poll fire several times with no idle crossings.
        try await Task.sleep(nanoseconds: 60_000_000)

        // Race-check: pull from the stream with a short timeout; should stay empty.
        let probe = Task<ActivityEvent?, Never> {
            for await event in source.events { return event }
            return nil
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        probe.cancel()
        await source.stop()

        // We can't await the probe value after cancel deterministically, so assert
        // that stop() fully finishes the stream and no events were buffered.
        var collected: [ActivityEvent] = []
        for await e in source.events {
            collected.append(e)
            if collected.count > 0 { break }
        }
        #expect(collected.isEmpty)
    }
}
