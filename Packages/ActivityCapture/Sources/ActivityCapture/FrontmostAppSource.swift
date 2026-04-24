import Foundation
import os
import ActivityCore
#if canImport(AppKit)
import AppKit
#endif

/// Snapshot of the currently frontmost application, decoupled from AppKit so
/// tests can inject fakes.
public struct FrontmostAppInfo: Hashable, Sendable {
    public let bundleID: String
    public let localizedName: String

    public init(bundleID: String, localizedName: String) {
        self.bundleID = bundleID
        self.localizedName = localizedName
    }
}

/// Protocol wrapper around `NSWorkspace` so we can inject fakes in tests.
public protocol FrontmostWorkspace: Sendable {
    func observeFrontmost(onChange: @escaping @Sendable (FrontmostAppInfo) -> Void)
    func stopObserving()
}

#if canImport(AppKit)
/// Unchecked-Sendable wrapper around a notification observer token so it can
/// live inside an `OSAllocatedUnfairLock` guarded state.
private struct ObserverBox: @unchecked Sendable {
    let token: NSObjectProtocol
}

/// Live adapter over `NSWorkspace`. Subscribes to
/// `didActivateApplicationNotification` and forwards bundleID + localized name.
public final class SystemFrontmostWorkspace: FrontmostWorkspace, @unchecked Sendable {
    private struct State: @unchecked Sendable {
        var box: ObserverBox?
        var handler: (@Sendable (FrontmostAppInfo) -> Void)?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func observeFrontmost(onChange: @escaping @Sendable (FrontmostAppInfo) -> Void) {
        state.withLock { $0.handler = onChange }

        let stateRef = self.state
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleID = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? ""
            guard !bundleID.isEmpty else { return }
            let handler = stateRef.withLock { $0.handler }
            handler?(FrontmostAppInfo(bundleID: bundleID, localizedName: name))
        }
        let box = ObserverBox(token: token)
        state.withLock { $0.box = box }
    }

    public func stopObserving() {
        let box = state.withLock { s -> ObserverBox? in
            let b = s.box
            s.box = nil
            s.handler = nil
            return b
        }
        if let box {
            NSWorkspace.shared.notificationCenter.removeObserver(box.token)
        }
    }
}
#endif

/// `CaptureSource` that emits a `frontmost` event each time a different
/// application becomes frontmost.
public final class FrontmostAppSource: CaptureSource, @unchecked Sendable {
    public let identifier: String = "frontmost"

    private struct State {
        var continuation: AsyncStream<ActivityEvent>.Continuation?
        var started: Bool = false
    }

    private let workspace: any FrontmostWorkspace
    private let clock: any Clock
    private let state = OSAllocatedUnfairLock(initialState: State())

    public let events: AsyncStream<ActivityEvent>

    public init(workspace: any FrontmostWorkspace, clock: any Clock = SystemClock()) {
        self.workspace = workspace
        self.clock = clock
        let (stream, continuation) = AsyncStream<ActivityEvent>.makeStream()
        self.events = stream
        state.withLock { $0.continuation = continuation }
    }

    public func start() async throws {
        let alreadyStarted = state.withLock { s -> Bool in
            if s.started { return true }
            s.started = true
            return false
        }
        if alreadyStarted { return }

        // Capture sendable copies for the closure.
        let clockRef = self.clock
        let stateRef = self.state

        workspace.observeFrontmost { info in
            let now = clockRef.now()
            let event = ActivityEvent(
                timestamp: now,
                source: .frontmost,
                subject: .app(bundleID: info.bundleID, name: info.localizedName)
            )
            let cont = stateRef.withLock { $0.continuation }
            cont?.yield(event)
        }
    }

    public func stop() async {
        workspace.stopObserving()
        let cont = state.withLock { s -> AsyncStream<ActivityEvent>.Continuation? in
            s.started = false
            let c = s.continuation
            s.continuation = nil
            return c
        }
        cont?.finish()
    }
}
