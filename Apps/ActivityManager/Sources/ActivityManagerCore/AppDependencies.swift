import Foundation
import os
import ActivityCore
import ActivityStore
import ActivityCapture
import ActivityLLM
import ActivityActions
import ActivityIPC

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
        // If the real store fails to open (permissions, corrupt file), fall
        // back to a temp store so the UI can still launch. Retry up to 3 times
        // on unique paths before giving up — only then crash with the real
        // error so the user sees a meaningful message instead of a force-try.
        if let real = try? SQLiteActivityStore(url: storeURL) {
            self.store = real
        } else {
            self.store = Self.openFallbackStore()
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
        // Privacy-first opt-in: destructive actions are off by default. The
        // Settings view restores the persisted user choice via setActionsEnabled.
        self.actions = ProcessTerminator(
            control: control,
            config: TerminatorConfig(actionsEnabled: false)
        )

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

    /// Forwards the master kill-switch to the action executor. Call from the
    /// Settings toggle.
    public func setActionsEnabled(_ enabled: Bool) {
        actions.setActionsEnabled(enabled)
    }

    /// Swap the registry's default provider to match the Settings picker.
    /// `.local` routes to the on-device Apple Foundation Models provider when
    /// available; `.null` falls back to the inert null provider; `.anthropic`
    /// reads the API key from Keychain (service ``KeychainStore/service``,
    /// account ``KeychainStore/anthropicAccount``) and constructs a real
    /// ``AnthropicProvider``. If no key is present the registry stays on
    /// ``NullLLMProvider`` so the UI degrades gracefully — the Settings view
    /// surfaces the missing-key state separately.
    public func setLLMProvider(_ choice: SettingsViewModel.ProviderChoice) {
        let next: any LLMProvider
        switch choice {
        case .anthropic:
            if let key = KeychainStore.read(account: KeychainStore.anthropicAccount),
               !key.isEmpty {
                next = AnthropicProvider(apiKey: key)
            } else {
                next = NullLLMProvider()
            }
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

    /// Last-resort store opener used when the production SQLite path is
    /// unwritable. Tries up to three uniquely-named temp paths before raising
    /// a fatal error with the underlying SQLite/GRDB message.
    private static func openFallbackStore() -> SQLiteActivityStore {
        var lastError: Error?
        for _ in 0..<3 {
            do {
                return try SQLiteActivityStore.temporary()
            } catch {
                lastError = error
            }
        }
        fatalError(
            "Unable to open ActivityManager store after 3 attempts: " +
            String(describing: lastError ?? NSError(domain: "ActivityManager", code: -1))
        )
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
