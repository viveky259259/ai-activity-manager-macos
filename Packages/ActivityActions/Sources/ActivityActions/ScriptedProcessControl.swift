import Foundation
import os
import ActivityCore

/// Test-support ``ProcessControl`` where behaviour can be scripted per-pid.
///
/// > Important: This type is intentionally public so test targets can import
/// > it, but it is **not** part of the package's supported API for production
/// > code. Do not instantiate from app binaries.
public final class ScriptedProcessControl: ProcessControl, @unchecked Sendable {

    /// Scripted record for a single process.
    public struct Entry: Sendable {
        public var pid: Int32
        public var bundleID: String
        public var isFrontmost: Bool
        public var isProtected: Bool
        public var hasUnsavedChanges: Bool
        /// Whether the process is currently "alive" in the fake OS.
        public var isAlive: Bool
        /// Strategies that will *fail* to terminate this process. All other
        /// strategies will terminate the process on first attempt.
        public var failingStrategies: Set<Action.KillStrategy>

        public init(
            pid: Int32,
            bundleID: String,
            isFrontmost: Bool = false,
            isProtected: Bool = false,
            hasUnsavedChanges: Bool = false,
            isAlive: Bool = true,
            failingStrategies: Set<Action.KillStrategy> = []
        ) {
            self.pid = pid
            self.bundleID = bundleID
            self.isFrontmost = isFrontmost
            self.isProtected = isProtected
            self.hasUnsavedChanges = hasUnsavedChanges
            self.isAlive = isAlive
            self.failingStrategies = failingStrategies
        }
    }

    private struct State {
        var entries: [Int32: Entry] = [:]
        var terminateLog: [(pid: Int32, strategy: Action.KillStrategy)] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(_ entries: [Entry] = []) {
        let seeded = entries
        state.withLock { s in
            for entry in seeded { s.entries[entry.pid] = entry }
        }
    }

    // MARK: - Scripting helpers

    public func register(_ entry: Entry) {
        state.withLock { $0.entries[entry.pid] = entry }
    }

    public func update(pid: Int32, _ mutate: @Sendable (inout Entry) -> Void) {
        state.withLock { s in
            guard var e = s.entries[pid] else { return }
            mutate(&e)
            s.entries[pid] = e
        }
    }

    public var terminateCalls: [(pid: Int32, strategy: Action.KillStrategy)] {
        state.withLock { $0.terminateLog }
    }

    public func entry(pid: Int32) -> Entry? {
        state.withLock { $0.entries[pid] }
    }

    // MARK: - ProcessControl

    public func runningApplications(bundleID: String) async -> [RunningProcess] {
        state.withLock { s in
            s.entries.values
                .filter { $0.bundleID == bundleID && $0.isAlive }
                .map { RunningProcess(pid: $0.pid, bundleID: $0.bundleID, isFrontmost: $0.isFrontmost) }
                .sorted { $0.pid < $1.pid }
        }
    }

    public func terminate(pid: Int32, strategy: Action.KillStrategy) async -> Bool {
        state.withLock { s in
            s.terminateLog.append((pid, strategy))
            guard var entry = s.entries[pid] else { return false }
            if entry.failingStrategies.contains(strategy) {
                // Strategy is scripted to fail: process stays alive.
                return false
            }
            entry.isAlive = false
            s.entries[pid] = entry
            return true
        }
    }

    public func isAlive(pid: Int32) async -> Bool {
        state.withLock { $0.entries[pid]?.isAlive ?? false }
    }

    public func hasUnsavedChanges(pid: Int32) async -> Bool {
        state.withLock { $0.entries[pid]?.hasUnsavedChanges ?? false }
    }

    public func isProtected(pid: Int32) async -> Bool {
        state.withLock { $0.entries[pid]?.isProtected ?? false }
    }
}
