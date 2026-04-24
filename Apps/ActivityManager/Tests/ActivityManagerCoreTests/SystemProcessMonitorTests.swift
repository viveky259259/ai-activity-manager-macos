import Foundation
import Testing
@testable import ActivityManagerCore

@Suite
@MainActor
struct SystemProcessMonitorTests {

    final class FakeSampler: SystemProcessSampler, @unchecked Sendable {
        private var scripted: [[ProcessRawSample]]
        private var index = 0

        init(sequences: [[ProcessRawSample]]) { self.scripted = sequences }

        func capture() -> [ProcessRawSample] {
            guard index < scripted.count else { return [] }
            defer { index += 1 }
            return scripted[index]
        }
    }

    @Test
    func firstSampleYieldsZeroCPU() {
        let sampler = FakeSampler(sequences: [[
            .init(pid: 1, name: "a", executablePath: "", bundleID: nil, user: "u",
                  cpuNanos: 100, memoryBytes: 0, threads: 1)
        ]])
        let monitor = SystemProcessMonitor(sampler: sampler)
        let out = monitor.sample(now: Date(timeIntervalSince1970: 0))
        #expect(out.count == 1)
        #expect(out[0].cpuPercent == 0)
    }

    @Test
    func secondSampleComputesDelta() {
        // 0.5s of CPU time over 1s wall clock = 50% (single-core).
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = t0.addingTimeInterval(1)
        let s0: ProcessRawSample = .init(
            pid: 1, name: "a", executablePath: "", bundleID: nil, user: "u",
            cpuNanos: 0, memoryBytes: 100, threads: 1
        )
        let s1: ProcessRawSample = .init(
            pid: 1, name: "a", executablePath: "", bundleID: nil, user: "u",
            cpuNanos: 500_000_000, memoryBytes: 200, threads: 2
        )
        let monitor = SystemProcessMonitor(sampler: FakeSampler(sequences: [[s0], [s1]]))
        _ = monitor.sample(now: t0)
        let out = monitor.sample(now: t1)
        #expect(out.count == 1)
        #expect(abs(out[0].cpuPercent - 50.0) < 0.001)
        #expect(out[0].memoryBytes == 200)
        #expect(out[0].threads == 2)
    }

    @Test
    func monotonicCounterProtectsAgainstRollback() {
        // If a sampler reports lower cumulative cpuNanos than last time (e.g.
        // PID reused for a new process), CPU % must clamp to 0 rather than
        // underflow into a huge UInt64.
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = t0.addingTimeInterval(1)
        let high: ProcessRawSample = .init(
            pid: 1, name: "a", executablePath: "", bundleID: nil, user: "u",
            cpuNanos: 1_000_000_000, memoryBytes: 0, threads: 1
        )
        let low: ProcessRawSample = .init(
            pid: 1, name: "a", executablePath: "", bundleID: nil, user: "u",
            cpuNanos: 100, memoryBytes: 0, threads: 1
        )
        let monitor = SystemProcessMonitor(sampler: FakeSampler(sequences: [[high], [low]]))
        _ = monitor.sample(now: t0)
        let out = monitor.sample(now: t1)
        #expect(out[0].cpuPercent == 0)
    }

    @Test
    func deadPIDsAreEvicted() {
        let t0 = Date(timeIntervalSince1970: 0)
        let s0: ProcessRawSample = .init(
            pid: 42, name: "gone", executablePath: "", bundleID: nil, user: "u",
            cpuNanos: 100, memoryBytes: 0, threads: 1
        )
        let monitor = SystemProcessMonitor(sampler: FakeSampler(sequences: [[s0], []]))
        _ = monitor.sample(now: t0)
        let second = monitor.sample(now: t0.addingTimeInterval(1))
        #expect(second.isEmpty)
        #expect(monitor.trackedPIDCount == 0)
    }
}
