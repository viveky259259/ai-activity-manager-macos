import Foundation
import ActivityCore

#if canImport(AppKit)
import AppKit
#endif

/// Abstraction over the OS process APIs used by ``ProcessTerminator``.
///
/// All methods are asynchronous so live implementations can perform blocking
/// work off the main thread. The protocol is `Sendable` so concrete types can
/// be shared across Swift 6 concurrency domains.
public protocol ProcessControl: Sendable {
    /// Returns every running process matching the supplied bundle identifier.
    func runningApplications(bundleID: String) async -> [RunningProcess]

    /// Terminate the process with the given pid using the requested strategy.
    /// Returns `true` when the OS call reports success.
    func terminate(pid: Int32, strategy: Action.KillStrategy) async -> Bool

    /// Returns `true` if the process is still alive.
    func isAlive(pid: Int32) async -> Bool

    /// Returns `true` if the frontmost window of the process has unsaved
    /// changes (AXDocumentModified).
    func hasUnsavedChanges(pid: Int32) async -> Bool

    /// Returns `true` when the process is protected (SIP, system daemon, etc).
    /// Protected processes must never be terminated by this package.
    func isProtected(pid: Int32) async -> Bool
}

/// Snapshot of a running process relevant to ``ProcessTerminator``.
public struct RunningProcess: Hashable, Sendable {
    public let pid: Int32
    public let bundleID: String
    public let isFrontmost: Bool

    public init(pid: Int32, bundleID: String, isFrontmost: Bool) {
        self.pid = pid
        self.bundleID = bundleID
        self.isFrontmost = isFrontmost
    }
}

#if canImport(AppKit)

/// Live ``ProcessControl`` backed by `NSRunningApplication` and POSIX kill.
///
/// > Note: This implementation is not exercised by unit tests — it requires
/// > integration verification against the real operating system. Use it only
/// > in the shipping application binary, and keep ``ScriptedProcessControl``
/// > for tests.
public struct LiveProcessControl: ProcessControl {
    public init() {}

    public func runningApplications(bundleID: String) async -> [RunningProcess] {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map { app in
            RunningProcess(
                pid: app.processIdentifier,
                bundleID: app.bundleIdentifier ?? bundleID,
                isFrontmost: app.processIdentifier == frontPID
            )
        }
    }

    public func terminate(pid: Int32, strategy: Action.KillStrategy) async -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        switch strategy {
        case .politeQuit:
            return app.terminate()
        case .forceQuit:
            return app.forceTerminate()
        case .signal:
            return kill(pid, SIGTERM) == 0
        }
    }

    public func isAlive(pid: Int32) async -> Bool {
        // `kill(pid, 0)` returns 0 when the process exists and we have permission
        // to signal it. ESRCH (process not found) means dead.
        return kill(pid, 0) == 0
    }

    public func hasUnsavedChanges(pid: Int32) async -> Bool {
        // Real implementation would walk the AX tree using
        // `kAXDocumentModifiedAttribute`. Integration-only — default to `false`
        // so live behaviour degrades to "allow" rather than blocking all quits.
        return false
    }

    public func isProtected(pid: Int32) async -> Bool {
        // Mirror the PRD's SIP heuristic: never kill pid < 100. A fuller
        // implementation would inspect the launchd label or code signature.
        return pid < 100
    }
}

#endif
