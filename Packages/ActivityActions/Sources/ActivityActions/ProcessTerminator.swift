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

    /// Last successful termination time per cooldown key. Bundle-targeted
    /// kills use `"bundle:<id>"`; pid-targeted kills use `"pid:<n>"` so the
    /// two namespaces cannot collide.
    private var lastKilledAt: [String: Date] = [:]

    /// Cooldown keys currently being processed. Prevents two concurrent
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

        let cooldownKey = "bundle:\(bundleID)"

        // Rail 2: Concurrency — only one in-flight request per bundle ID.
        if inFlight.contains(cooldownKey) {
            return .refused(reason: "cooldown")
        }

        // Rail 3: Cooldown window.
        if isInCooldown(key: cooldownKey) {
            return .refused(reason: "cooldown")
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

        return await runTermination(
            pid: target.pid,
            cooldownKey: cooldownKey,
            strategy: strategy,
            force: force
        )
    }

    /// Pid-direct termination path used by the MCP layer (PRD-10).
    ///
    /// No bundle-based target resolution — the caller supplies the pid directly
    /// (for instance after walking a `list_processes` result). Safety rails stay
    /// the same: global switch, SIP, unsaved changes on non-force strategies,
    /// per-pid cooldown, escalation when `force == true`.
    public func killProcess(
        pid: Int32,
        strategy: Action.KillStrategy,
        force: Bool
    ) async -> ActionOutcome {
        // Rail 1: Global kill switch.
        guard actionsEnabled else {
            return .refused(reason: "global kill switch")
        }

        let cooldownKey = "pid:\(pid)"

        // Rail 2: Concurrency guard per-pid.
        if inFlight.contains(cooldownKey) {
            return .refused(reason: "cooldown")
        }

        // Rail 3: Cooldown window.
        if isInCooldown(key: cooldownKey) {
            return .refused(reason: "cooldown")
        }

        // Rail 4: SIP / protected processes. pid < 100 is the live heuristic.
        if await control.isProtected(pid: pid) {
            return .notPermitted(reason: "protected process")
        }

        // Target existence check. Without a bundle we can't enumerate "which
        // one" — `isAlive` is our only probe. If the pid is gone or was never
        // there, fall through to refused so the caller gets a clear signal.
        guard await control.isAlive(pid: pid) else {
            return .refused(reason: "no matching process")
        }

        // Rail 5: Unsaved changes — unlike bundle-targeted kills we can't
        // decide based on frontmost-ness (we don't know the window context
        // for an arbitrary pid). Apply the unsaved-changes guard whenever the
        // strategy isn't forceQuit; callers who need to bypass it must pass
        // `strategy: .forceQuit`.
        if strategy != .forceQuit {
            let unsaved = await control.hasUnsavedChanges(pid: pid)
            if unsaved {
                return .refused(reason: "unsaved changes")
            }
        }

        return await runTermination(
            pid: pid,
            cooldownKey: cooldownKey,
            strategy: strategy,
            force: force
        )
    }

    // MARK: - Shared termination loop

    private func isInCooldown(key: String) -> Bool {
        guard let last = lastKilledAt[key] else { return false }
        return clock.now().timeIntervalSince(last) < config.effectiveCooldown
    }

    private func runTermination(
        pid: Int32,
        cooldownKey: String,
        strategy: Action.KillStrategy,
        force: Bool
    ) async -> ActionOutcome {
        inFlight.insert(cooldownKey)
        defer { inFlight.remove(cooldownKey) }

        let firstOK = await control.terminate(pid: pid, strategy: strategy)
        if firstOK {
            let alive = await control.isAlive(pid: pid)
            if !alive {
                lastKilledAt[cooldownKey] = clock.now()
                return .succeeded
            }
        }

        // Wait out grace period, polling for process death.
        let deadline = Date().addingTimeInterval(config.graceSeconds)
        while Date() < deadline {
            let alive = await control.isAlive(pid: pid)
            if !alive {
                lastKilledAt[cooldownKey] = clock.now()
                return .succeeded
            }
            try? await Task.sleep(nanoseconds: UInt64(config.pollInterval * 1_000_000_000))
        }

        // Still alive. Escalate if caller opted in and we weren't already forcing.
        if force && strategy != .forceQuit {
            let forceOK = await control.terminate(pid: pid, strategy: .forceQuit)
            let alive = await control.isAlive(pid: pid)
            if forceOK && !alive {
                lastKilledAt[cooldownKey] = clock.now()
                return .escalated(previous: strategy.rawValue)
            }
            return .refused(reason: "escalation failed")
        }

        return .refused(reason: "process still alive")
    }
}
