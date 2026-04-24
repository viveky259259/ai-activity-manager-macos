import Foundation

/// Turns a stream of `ProcessRawSample`s (cumulative CPU counters) into
/// `SystemProcess` rows with a CPU % computed across wall-clock time between
/// consecutive samples.
@MainActor
public final class SystemProcessMonitor {
    private struct Prev {
        let cpuNanos: UInt64
    }

    private let sampler: any SystemProcessSampler
    private var prev: [Int32: Prev] = [:]
    private var lastSampledAt: Date?

    public init(sampler: any SystemProcessSampler) {
        self.sampler = sampler
    }

    /// Visible for tests: how many PIDs the monitor is tracking between samples.
    public var trackedPIDCount: Int { prev.count }

    /// Captures a fresh sample from the underlying sampler and returns processed
    /// rows. The first call seeds the cache and reports 0 % CPU for every PID.
    public func sample(now: Date) -> [SystemProcess] {
        let samples = sampler.capture()
        let elapsed = lastSampledAt.map { now.timeIntervalSince($0) } ?? 0

        var out: [SystemProcess] = []
        out.reserveCapacity(samples.count)
        for s in samples {
            let percent: Double
            if let previous = prev[s.pid], elapsed > 0 {
                // Clamp to zero on non-monotonic readings (PID reuse or sampler
                // quirks). Reporting a negative % would poison downstream sort.
                let delta = s.cpuNanos >= previous.cpuNanos
                    ? Double(s.cpuNanos - previous.cpuNanos)
                    : 0
                percent = (delta / (elapsed * 1_000_000_000)) * 100
            } else {
                percent = 0
            }
            out.append(SystemProcess(
                id: s.pid,
                name: s.name,
                executablePath: s.executablePath,
                bundleID: s.bundleID,
                user: s.user,
                cpuPercent: percent,
                memoryBytes: s.memoryBytes,
                threads: s.threads,
                isRestricted: s.isRestricted
            ))
        }

        // Replace the cache wholesale so dead PIDs drop out automatically.
        var next: [Int32: Prev] = [:]
        next.reserveCapacity(samples.count)
        for s in samples { next[s.pid] = Prev(cpuNanos: s.cpuNanos) }
        prev = next
        lastSampledAt = now
        return out
    }
}
