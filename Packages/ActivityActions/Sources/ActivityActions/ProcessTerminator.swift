import Foundation
import os
import ActivityCore

/// Configuration for ``ProcessTerminator``.
public struct TerminatorConfig: Sendable {
    /// Master switch. When `false`, every request returns
    /// ``ActionOutcome/refused(reason:)`` with reason `"global kill switch"`.
    /// Defaults to `true`. The switch is dynamic — use
    /// ``ProcessTerminator/setActionsEnabled(_:)``.
    public var actionsEnabled: Bool

    /// Minimum interval between two terminations targeting the same bundle ID.
    /// Values below ``minCooldown`` are clamped up.
    public var cooldown: TimeInterval

    /// Hard floor on ``cooldown``. Cannot be overridden by callers.
    public let minCooldown: TimeInterval

    /// Seconds to wait between polite quit and force-quit escalation.
    public var graceSeconds: TimeInterval

    /// Polling interval while waiting for the polite-quit grace period.
    /// Exposed for tests; production callers should accept the default.
    public var pollInterval: TimeInterval

    public init(
        actionsEnabled: Bool = true,
        cooldown: TimeInterval = 60,
        minCooldown: TimeInterval = 30,
        graceSeconds: TimeInterval = 10,
        pollInterval: TimeInterval = 0.05
    ) {
        self.actionsEnabled = actionsEnabled
        self.minCooldown = minCooldown
        self.cooldown = max(cooldown, minCooldown)
        self.graceSeconds = graceSeconds
        self.pollInterval = pollInterval
    }

    /// Effective cooldown, honouring the hard floor.
    public var effectiveCooldown: TimeInterval {
        max(cooldown, minCooldown)
    }
}

/// ``ActionExecutor`` that terminates running macOS apps with strict safety
/// rails (SIP, unsaved changes, cooldown, global kill switch, escalation).
///
/// Other ``Action`` cases are refused — compose executors if you need them.
public actor ProcessTerminator: ActionExecutor {

    private let control: ProcessControl
    private let clock: Clock
    private var config: TerminatorConfig
    private let enabledFlag: OSAllocatedUnfairLock<Bool>

    /// Last successful termination time per bundle ID. Used for cooldown.
    private var lastKilledAt: [String: Date] = [:]

    /// Bundle IDs currently being processed. Prevents two concurrent
    /// terminations from racing through the cooldown window.
    private var inFlight: Set<String> = []

    public init(
        control: ProcessControl,
        clock: Clock = SystemClock(),
        config: TerminatorConfig = TerminatorConfig()
    ) {
        self.control = control
        self.clock = clock
        self.config = config
        self.enabledFlag = OSAllocatedUnfairLock(initialState: config.actionsEnabled)
    }

    /// Sendable setter for the global kill switch.
    public nonisolated func setActionsEnabled(_ enabled: Bool) {
        enabledFlag.withLock { $0 = enabled }
    }

    /// Current value of the global kill switch (thread-safe).
    public nonisolated var actionsEnabled: Bool {
        enabledFlag.withLock { $0 }
    }

    // MARK: - ActionExecutor

    public func execute(_ action: Action) async throws -> ActionOutcome {
        switch action {
        case let .killApp(bundleID, strategy, force):
            return await killApp(bundleID: bundleID, strategy: strategy, force: force)
        default:
            return .refused(reason: "not handled by this executor")
        }
    }

    // MARK: - Implementation

    private func killApp(
        bundleID: String,
        strategy: Action.KillStrategy,
        force: Bool
    ) async -> ActionOutcome {
        // Rail 1: Global kill switch.
        guard actionsEnabled else {
            return .refused(reason: "global kill switch")
        }

        // Rail 2: Concurrency — only one in-flight request per bundle ID.
        if inFlight.contains(bundleID) {
            return .refused(reason: "cooldown")
        }

        // Rail 3: Cooldown window.
        let now = clock.now()
        if let last = lastKilledAt[bundleID] {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < config.effectiveCooldown {
                return .refused(reason: "cooldown")
            }
        }

        // Resolve target.
        let candidates = await control.runningApplications(bundleID: bundleID)
        guard let target = candidates.first else {
            return .refused(reason: "no matching process")
        }

        // Rail 4: SIP / protected processes.
        if await control.isProtected(pid: target.pid) {
            return .notPermitted(reason: "protected process")
        }

        // Rail 5: Unsaved changes on frontmost window with non-force strategy.
        if target.isFrontmost && strategy != .forceQuit {
            let unsaved = await control.hasUnsavedChanges(pid: target.pid)
            if unsaved {
                return .refused(reason: "unsaved changes")
            }
        }

        inFlight.insert(bundleID)
        defer { inFlight.remove(bundleID) }

        // First attempt: requested strategy.
        let firstOK = await control.terminate(pid: target.pid, strategy: strategy)
        if firstOK {
            let alive = await control.isAlive(pid: target.pid)
            if !alive {
                lastKilledAt[bundleID] = clock.now()
                return .succeeded
            }
        }

        // Wait out grace period, polling for process death. Uses wall-clock
        // because `Task.sleep` advances in real time; the injected `clock` is
        // reserved for cooldown accounting and event timestamps (so tests
        // can drive cooldown deterministically without stalling this loop).
        let deadline = Date().addingTimeInterval(config.graceSeconds)
        while Date() < deadline {
            let alive = await control.isAlive(pid: target.pid)
            if !alive {
                lastKilledAt[bundleID] = clock.now()
                return .succeeded
            }
            try? await Task.sleep(nanoseconds: UInt64(config.pollInterval * 1_000_000_000))
        }

        // Still alive. Escalate if caller opted in and we weren't already forcing.
        if force && strategy != .forceQuit {
            let forceOK = await control.terminate(pid: target.pid, strategy: .forceQuit)
            let alive = await control.isAlive(pid: target.pid)
            if forceOK && !alive {
                lastKilledAt[bundleID] = clock.now()
                return .escalated(previous: strategy.rawValue)
            }
            return .refused(reason: "escalation failed")
        }

        return .refused(reason: "process still alive")
    }
}
