import Foundation
import os
import ActivityCore
import ActivityStore
import ActivityCapture
import ActivityLLM
import ActivityActions
import ActivityIPC
import ActivityMCP
import ActivityWebGateway

/// Composition root for the ActivityManager app.
///
/// Holds the long-lived adapter instances wired together at app start. Kept as
/// a final class with `@unchecked Sendable` because several of the underlying
/// adapter types (e.g. `IPCServer`, `CaptureCoordinator`) are themselves
/// `@unchecked Sendable`. Internal mutable state is guarded by
/// `OSAllocatedUnfairLock`.
public final class AppDependencies: @unchecked Sendable {
    public let store: SQLiteActivityStore
    public let capture: CaptureCoordinator
    public let llm: DefaultLLMProviderRegistry
    public let actions: ProcessTerminator
    public let permissions: any PermissionsChecker

    /// Live process sampler shared by the Processes window viewmodel and the
    /// IPC handler (so MCP's `list_processes` sees the same pid universe the
    /// user sees in the UI). Defaults to `LiveSystemProcessSampler`.
    public let sampler: any SystemProcessSampler

    /// System-wide memory snapshot provider, injected as a closure so tests
    /// can swap it without touching Mach APIs. Defaults to
    /// `SystemMemorySource.snapshot`.
    public let memorySource: @Sendable () -> SystemMemorySource.Snapshot?

    /// Observable state the menu bar reads to show what the user is doing now.
    /// Updated on the main actor from the capture event pump.
    @MainActor public let current: CurrentActivityState

    /// Bootstrap state: `true` once `bootstrap()` has attached the event pump.
    private let bootstrapped = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// IPC server is initialised lazily (it needs an IPCHandler that references
    /// the other adapters via use-cases). Guarded by a lock for Swift 6 strict
    /// concurrency.
    private let ipcServerState = OSAllocatedUnfairLock<IPCServer?>(initialState: nil)

    public var ipcServer: IPCServer? {
        ipcServerState.withLock { $0 }
    }

    public func setIPCServer(_ server: IPCServer) {
        ipcServerState.withLock { $0 = server }
    }

    /// Live MCP audit broadcaster — fans `tools/call` outcomes out to the web
    /// gateway's WebSocket subscribers. Replaces `NullAuditLogger` in
    /// `DefaultMCPHandler` once the host wires MCP into the daemon.
    public let auditBroadcaster = BroadcastingAuditLogger()

    /// Web gateway is initialised in `bootstrap()` after the IPC handler
    /// exists. Guarded for Swift 6 strict concurrency.
    private let gatewayState = OSAllocatedUnfairLock<WebGateway?>(initialState: nil)

    public var webGateway: WebGateway? {
        gatewayState.withLock { $0 }
    }

    @MainActor
    public init(
        sampler: (any SystemProcessSampler)? = nil,
        memorySource: (@Sendable () -> SystemMemorySource.Snapshot?)? = nil
    ) {
        // Store — ensure the containing directory exists before opening SQLite.
        let storeURL = Self.defaultStoreURL()
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // If the real store fails to open (permissions, corrupt file), fall back
        // to a temp store so the UI can still launch.
        if let real = try? SQLiteActivityStore(url: storeURL) {
            self.store = real
        } else {
            // swiftlint:disable:next force_try
            self.store = try! SQLiteActivityStore.temporary()
        }

        // Capture — wire the live macOS sources. FrontmostAppSource uses
        // NSWorkspace notifications (no permission prompt). IdleSource uses
        // CGEventSource HID idle timer (no permission prompt on macOS 14+).
        let frontmost: CaptureSource
        let idle: CaptureSource
        #if canImport(AppKit)
        frontmost = FrontmostAppSource(workspace: SystemFrontmostWorkspace())
        #else
        frontmost = FrontmostAppSource(workspace: NoopWorkspace())
        #endif
        idle = IdleSource()
        self.capture = CaptureCoordinator(sources: [frontmost, idle])

        // LLM — default to a null provider so the registry is never empty. The
        // app layer can swap in `AnthropicProvider` once an API key is loaded.
        self.llm = DefaultLLMProviderRegistry(default: NullLLMProvider())

        // Actions — platform-dependent live control is AppKit-gated.
        let control: ProcessControl
        #if canImport(AppKit)
        control = LiveProcessControl()
        #else
        control = ScriptedProcessControl()
        #endif
        self.actions = ProcessTerminator(control: control)

        self.permissions = SystemPermissionsChecker()
        self.current = CurrentActivityState()

        self.sampler = sampler ?? LiveSystemProcessSampler()
        self.memorySource = memorySource ?? { SystemMemorySource.snapshot() }
    }

    /// Starts capture and begins persisting every event into the SQLite store.
    /// Safe to call more than once — only the first call attaches the pump.
    @MainActor
    public func bootstrap() async {
        let firstCall = bootstrapped.withLock { flag -> Bool in
            if flag { return false }
            flag = true
            return true
        }
        guard firstCall else { return }

        await capture.start()

        let events = capture.events
        let store = self.store
        let current = self.current
        Task.detached { [store, current] in
            for await event in events {
                do {
                    try await store.append([event])
                } catch {
                    // Dropped event — persistence errors here are non-fatal;
                    // the UI still reflects live state from the same stream.
                }
                await current.update(with: event)
            }
        }

        startIPCServer()
        await startWebGateway()
    }

    /// Stands up the Mach-service XPC listener so CLI/MCP clients can reach
    /// the daemon. Safe to call more than once — `bootstrap()` gates this.
    private func startIPCServer() {
        let handler = ProductionIPCHandler(
            store: store,
            terminator: actions,
            sampler: sampler,
            permissions: permissions,
            memorySource: memorySource,
            captureStatuses: { [capture] in capture.statuses }
        )
        let server = IPCServer(handler: handler)
        let listener = server.makeMachServiceListener()
        listener.resume()
        setIPCServer(server)
    }

    /// Stands up the HTTP/WebSocket gateway that backs the Flutter web UI.
    /// Bound to localhost only — no remote network exposure.
    private func startWebGateway() async {
        let handler = ProductionIPCHandler(
            store: store,
            terminator: actions,
            sampler: sampler,
            permissions: permissions,
            memorySource: memorySource,
            captureStatuses: { [capture] in capture.statuses }
        )
        let staticRoot = Self.flutterWebRoot()
        let gateway = WebGateway(
            handler: handler,
            broadcaster: auditBroadcaster,
            staticRoot: staticRoot,
            host: "127.0.0.1",
            port: 8765
        )
        do {
            try await gateway.start()
            gatewayState.withLock { $0 = gateway }
        } catch {
            // Port collision or sandbox denial — non-fatal; the menu-bar UI
            // and XPC listener still work without the web view.
        }
    }

    /// Looks for the Flutter `web/` build output beside the daemon binary so
    /// the gateway can serve `/index.html` and the bundled assets. Returns
    /// `nil` if no build is present — the gateway will only expose the API.
    private static func flutterWebRoot() -> URL? {
        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/ActivityManager/web"),
            Bundle.main.resourceURL?.appendingPathComponent("web"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Forwards the master kill-switch to the action executor. Call from the
    /// Settings toggle.
    public func setActionsEnabled(_ enabled: Bool) {
        actions.setActionsEnabled(enabled)
    }

    /// Swap the registry's default provider to match the Settings picker.
    /// `.local` routes to the on-device Apple Foundation Models provider when
    /// available; `.null` falls back to the inert null provider.
    ///
    /// `.anthropic` is deferred until API-key loading is wired up — today it
    /// behaves like `.null` so the UI doesn't crash if the user selects it.
    public func setLLMProvider(_ choice: SettingsViewModel.ProviderChoice) {
        let next: any LLMProvider
        switch choice {
        case .anthropic:
            next = NullLLMProvider()
        case .local:
            if #available(macOS 26.0, *) {
                next = AppleFoundationModelsProvider()
            } else {
                next = NullLLMProvider()
            }
        case .null:
            next = NullLLMProvider()
        }
        llm.setDefault(next)
    }

    /// URL where the production SQLite database lives. Derived from the user's
    /// home directory; the enclosing Application Support folder is created
    /// on-demand by the caller.
    public static func defaultStoreURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/ActivityManager/activity.sqlite")
    }
}

/// Inert `LLMProvider` used as the registry's fallback before a real provider
/// is configured. Returns empty responses so view-models can render stable UI.
public final class NullLLMProvider: LLMProvider, Sendable {
    public let identifier: String = "null"
    public let isLocal: Bool = true

    public init() {}

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(text: "", inputTokens: 0, outputTokens: 0, model: identifier)
    }
}

#if !canImport(AppKit)
/// Non-AppKit fallback so the package still compiles on Linux CI.
private struct NoopWorkspace: FrontmostWorkspace {
    func observeFrontmost(onChange: @escaping @Sendable (FrontmostAppInfo) -> Void) {}
    func stopObserving() {}
}
#endif
