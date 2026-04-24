import Foundation
import Darwin
#if canImport(AppKit)
import AppKit
#endif

/// Drives the Activity-Monitor-style Processes window.
///
/// Owns a `SystemProcessMonitor` that periodically samples every visible PID,
/// exposes the current snapshot for sorting / filtering, and provides quit
/// helpers for a selected row.
@MainActor
@Observable
public final class RunningProcessesViewModel {
    public private(set) var processes: [SystemProcess] = []
    public var searchText: String = ""
    public var isKillSwitchEngaged: Bool = false

    private let monitor: SystemProcessMonitor
    private let clock: @Sendable () -> Date

    public init(
        sampler: any SystemProcessSampler = LiveSystemProcessSampler(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.monitor = SystemProcessMonitor(sampler: sampler)
        self.clock = clock
    }

    public func refresh() {
        self.processes = monitor.sample(now: clock())
    }

    /// Case-insensitive filter on name / bundle ID / executable path / user /
    /// numeric PID so users can type "501", "safari", or "root".
    public var filtered: [SystemProcess] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return processes }
        return processes.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || ($0.bundleID?.localizedCaseInsensitiveContains(q) ?? false)
                || $0.executablePath.localizedCaseInsensitiveContains(q)
                || $0.user.localizedCaseInsensitiveContains(q)
                || String($0.id).contains(q)
        }
    }

    public struct Totals: Sendable {
        public let total: Int
        public let visible: Int
        /// System-wide used memory (wired + compressed + app) from
        /// `host_statistics64`. Matches Activity Monitor's "Memory Used".
        /// `nil` if the kernel call failed.
        public let systemMemoryUsedBytes: UInt64?
        public let systemMemoryTotalBytes: UInt64?
        public let totalCPU: Double
    }

    public var totals: Totals {
        let vis = filtered
        let sysMem = SystemMemorySource.snapshot()
        return Totals(
            total: processes.count,
            visible: vis.count,
            systemMemoryUsedBytes: sysMem?.usedBytes,
            systemMemoryTotalBytes: sysMem?.totalBytes,
            totalCPU: vis.reduce(0) { $0 + $1.cpuPercent }
        )
    }

    // MARK: - Actions

    public enum QuitResult: Sendable {
        case sent
        case refusedKillSwitch
        case noSuchProcess(pid: Int32)
        case failed(errno: Int32)
    }

    /// Sends `SIGTERM` (or `SIGKILL` if `force`) to the given PID. Honours the
    /// global kill switch set by the Settings toggle — `isKillSwitchEngaged`
    /// must be `false` for anything to fire.
    @discardableResult
    public func quit(pid: Int32, force: Bool) -> QuitResult {
        guard !isKillSwitchEngaged else { return .refusedKillSwitch }
        let sig: Int32 = force ? SIGKILL : SIGTERM
        let r = Darwin.kill(pid, sig)
        if r == 0 { return .sent }
        let err = errno
        if err == ESRCH { return .noSuchProcess(pid: pid) }
        return .failed(errno: err)
    }
}
