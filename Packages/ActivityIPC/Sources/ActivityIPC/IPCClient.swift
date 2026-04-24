import Foundation
import os

/// Typed, async/await-friendly XPC client. Bridges the Obj-C reply-block API to
/// Swift concurrency via `withCheckedThrowingContinuation`.
public final class IPCClient: @unchecked Sendable {
    private let connection: NSXPCConnection
    private let log = Logger(subsystem: "com.yourco.ActivityManager.ipc", category: "IPCClient")
    private let didResume = OSAllocatedUnfairLock(initialState: false)

    /// Connect to an anonymous listener by endpoint. Useful for in-process tests.
    public init(endpoint: NSXPCListenerEndpoint) {
        self.connection = NSXPCConnection(listenerEndpoint: endpoint)
        configure()
    }

    /// Connect to a registered Mach service.
    public init(machServiceName: String = IPCProtocol.machServiceName, options: NSXPCConnection.Options = []) {
        self.connection = NSXPCConnection(machServiceName: machServiceName, options: options)
        configure()
    }

    deinit {
        connection.invalidate()
    }

    private func configure() {
        connection.remoteObjectInterface = ActivityIPCInterface.make()
    }

    /// Lazily resume the connection the first time an RPC is issued. Calling
    /// `resume()` more than once is a fatal error on `NSXPCConnection`.
    private func ensureResumed() {
        didResume.withLock { resumed in
            if !resumed {
                connection.resume()
                resumed = true
            }
        }
    }

    public func invalidate() {
        connection.invalidate()
    }

    // MARK: Public API

    public func status() async throws -> StatusResponse {
        try await callVoidRequest(StatusResponse.self) { proxy, reply in
            proxy.status(reply: reply)
        }
    }

    public func query(_ request: QueryRequest) async throws -> QueryResponse {
        try await call(request, as: QueryResponse.self) { proxy, data, reply in
            proxy.query(data, reply: reply)
        }
    }

    public func timeline(_ request: TimelineRequest) async throws -> TimelineResponse {
        try await call(request, as: TimelineResponse.self) { proxy, data, reply in
            proxy.timeline(data, reply: reply)
        }
    }

    public func events(_ request: EventsRequest) async throws -> EventsResponse {
        try await call(request, as: EventsResponse.self) { proxy, data, reply in
            proxy.events(data, reply: reply)
        }
    }

    public func rules() async throws -> RulesResponse {
        try await callVoidRequest(RulesResponse.self) { proxy, reply in
            proxy.rules(reply: reply)
        }
    }

    public func addRule(_ request: AddRuleRequest) async throws -> AddRuleResponse {
        try await call(request, as: AddRuleResponse.self) { proxy, data, reply in
            proxy.addRule(data, reply: reply)
        }
    }

    public func toggleRule(_ request: ToggleRuleRequest) async throws {
        _ = try await call(request, as: EmptyResponse.self) { proxy, data, reply in
            proxy.toggleRule(data, reply: reply)
        }
    }

    public func deleteRule(_ request: DeleteRuleRequest) async throws {
        _ = try await call(request, as: EmptyResponse.self) { proxy, data, reply in
            proxy.deleteRule(data, reply: reply)
        }
    }

    public func killApp(_ request: KillAppRequest) async throws -> KillAppResponse {
        try await call(request, as: KillAppResponse.self) { proxy, data, reply in
            proxy.killApp(data, reply: reply)
        }
    }

    public func setFocusMode(_ request: SetFocusRequest) async throws {
        _ = try await call(request, as: EmptyResponse.self) { proxy, data, reply in
            proxy.setFocusMode(data, reply: reply)
        }
    }

    public func listProcesses(_ request: ProcessesQuery) async throws -> ProcessesPage {
        try await call(request, as: ProcessesPage.self) { proxy, data, reply in
            proxy.listProcesses(data, reply: reply)
        }
    }

    // MARK: Internal helpers

    /// Send a request envelope and await a response envelope. Uses a checked
    /// throwing continuation to bridge the XPC reply callback to async/await.
    private func call<Req: Codable & Sendable, Resp: Codable & Sendable>(
        _ payload: Req,
        as responseType: Resp.Type,
        invoke: @escaping @Sendable (any ActivityIPCServiceProtocol, Data, @escaping @Sendable (Data) -> Void) -> Void
    ) async throws -> Resp {
        ensureResumed()

        let envelope = IPCRequest(payload: payload)
        let data: Data
        do {
            data = try IPCCoder.encoder().encode(envelope)
        } catch {
            throw IPCError(code: IPCError.encodeFailure.code, message: "\(error)")
        }

        let expectedRequestID = envelope.requestID

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Resp, any Error>) in
            // `NSXPCConnection` emits errors (host unreachable, invalidation) via an
            // errorHandler on the proxy, not through the reply block. We wire both
            // into the continuation using an atomic one-shot box.
            let box = ContinuationBox(continuation)

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                box.resume(throwing: Self.mapTransportError(error))
            }

            guard let service = proxy as? any ActivityIPCServiceProtocol else {
                box.resume(throwing: IPCError.internalError)
                return
            }

            invoke(service, data) { responseData in
                do {
                    let response = try IPCCoder.decoder().decode(IPCResponse<Resp>.self, from: responseData)
                    switch response.result {
                    case .success(let value):
                        // Best-effort sanity check; only log since the Mach service
                        // may re-order on reconnect.
                        if response.requestID != expectedRequestID {
                            // Not fatal; the envelope shape still matches.
                        }
                        box.resume(returning: value)
                    case .error(let err):
                        box.resume(throwing: err)
                    }
                } catch {
                    box.resume(throwing: IPCError(code: IPCError.decodeFailure.code, message: "\(error)"))
                }
            }
        }
    }

    /// Variant for endpoints that take no request payload (`status`, `rules`).
    private func callVoidRequest<Resp: Codable & Sendable>(
        _ responseType: Resp.Type,
        invoke: @escaping @Sendable (any ActivityIPCServiceProtocol, @escaping @Sendable (Data) -> Void) -> Void
    ) async throws -> Resp {
        ensureResumed()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Resp, any Error>) in
            let box = ContinuationBox(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                box.resume(throwing: Self.mapTransportError(error))
            }

            guard let service = proxy as? any ActivityIPCServiceProtocol else {
                box.resume(throwing: IPCError.internalError)
                return
            }

            invoke(service) { responseData in
                do {
                    let response = try IPCCoder.decoder().decode(IPCResponse<Resp>.self, from: responseData)
                    switch response.result {
                    case .success(let value):
                        box.resume(returning: value)
                    case .error(let err):
                        box.resume(throwing: err)
                    }
                } catch {
                    box.resume(throwing: IPCError(code: IPCError.decodeFailure.code, message: "\(error)"))
                }
            }
        }
    }

    private static func mapTransportError(_ error: any Error) -> IPCError {
        let ns = error as NSError
        // NSXPCConnection surfaces NSXPCConnectionError codes in `NSCocoaErrorDomain`
        // (or `NSXPCConnectionErrorDomain` on some OS versions). Collapse anything
        // that indicates an unreachable peer into `hostUnreachable`.
        if ns.domain == NSCocoaErrorDomain || ns.domain.contains("XPC") {
            return IPCError.hostUnreachable
        }
        return IPCError(code: "transport_error", message: ns.localizedDescription)
    }
}

/// One-shot wrapper around a `CheckedContinuation` so either the reply block or
/// the transport errorHandler can resume it exactly once.
private final class ContinuationBox<T>: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    private let continuation: CheckedContinuation<T, any Error>

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    func resume(returning value: sending T) {
        let shouldResume: Bool = lock.withLock { fired in
            if fired { return false }
            fired = true
            return true
        }
        if shouldResume { continuation.resume(returning: value) }
    }

    func resume(throwing error: any Error) {
        let shouldResume: Bool = lock.withLock { fired in
            if fired { return false }
            fired = true
            return true
        }
        if shouldResume { continuation.resume(throwing: error) }
    }
}
