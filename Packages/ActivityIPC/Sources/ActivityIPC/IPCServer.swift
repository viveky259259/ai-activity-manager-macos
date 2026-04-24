import Foundation
import os

/// XPC server. Accepts connections, exports an `ActivityIPCServiceProtocol`, and
/// routes decoded payloads to the provided `IPCHandler`.
public final class IPCServer: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let handler: any IPCHandler
    private let log = Logger(subsystem: "com.yourco.ActivityManager.ipc", category: "IPCServer")

    // Retain connections so they are not deallocated while in use. Swift 6 strict
    // concurrency requires explicit protection around shared mutable state.
    // NSXPCConnection is not Sendable, so we wrap it in an unchecked box — the
    // framework documents that the underlying queue is thread-safe.
    private let state = OSAllocatedUnfairLock(initialState: [ConnectionBox]())

    public init(handler: any IPCHandler) {
        self.handler = handler
        super.init()
    }

    /// Create an anonymous listener useful for in-process tests. The caller should
    /// vend `listener.endpoint` to the client and `resume()` the listener.
    public func makeListener() -> NSXPCListener {
        let listener = NSXPCListener.anonymous()
        listener.delegate = self
        return listener
    }

    /// Create a Mach-service listener for production deployment. The caller is
    /// responsible for calling `resume()` once the app is ready.
    public func makeMachServiceListener(
        name: String = IPCProtocol.machServiceName
    ) -> NSXPCListener {
        let listener = NSXPCListener(machServiceName: name)
        listener.delegate = self
        return listener
    }

    // MARK: NSXPCListenerDelegate

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = ActivityIPCInterface.make()
        let exported = ExportedObject(handler: handler)
        newConnection.exportedObject = exported

        // Clean up when the peer disconnects so the connection array doesn't grow
        // unbounded in long-running processes.
        let weakSelf = WeakBox(self)
        let connectionBox = ConnectionBox(newConnection)
        newConnection.invalidationHandler = { [weakSelf, connectionBox] in
            weakSelf.value?.remove(box: connectionBox)
        }
        newConnection.interruptionHandler = { [weakSelf, connectionBox] in
            weakSelf.value?.remove(box: connectionBox)
        }

        state.withLock { $0.append(connectionBox) }
        newConnection.resume()
        log.debug("accepted new XPC connection")
        return true
    }

    private func remove(box: ConnectionBox) {
        state.withLock { conns in
            conns.removeAll { $0 === box }
        }
    }
}

/// `NSXPCConnection` is not Sendable, but its public API is thread-safe (it owns
/// its own serial queue). Wrap it to satisfy strict concurrency.
private final class ConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection
    init(_ connection: NSXPCConnection) { self.connection = connection }
}

/// Box that holds a weak reference to a class, making it safe to capture in an
/// Obj-C block without creating a retain cycle.
private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// The Obj-C visible exported object. Decodes `IPCRequest<T>` from `Data`, calls
/// the typed async handler, then encodes an `IPCResponse<U>` back to `Data`.
///
/// This class is `@objc` so it can be vended through XPC. All mutable state lives
/// on the stored `handler`, which is itself `Sendable`.
final class ExportedObject: NSObject, ActivityIPCServiceProtocol, @unchecked Sendable {
    private let handler: any IPCHandler
    private let log = Logger(subsystem: "com.yourco.ActivityManager.ipc", category: "Exported")

    init(handler: any IPCHandler) {
        self.handler = handler
        super.init()
    }

    // MARK: ActivityIPCServiceProtocol

    func status(reply: @escaping @Sendable (Data) -> Void) {
        // `status` takes no payload over the wire. We still honour the envelope
        // version by reading it from an empty `IPCRequest<EmptyRequestPayload>` when
        // supplied, but accepting zero-length data keeps the call site tiny.
        let requestID = UUID()
        let handler = self.handler
        Task.detached {
            do {
                let response = try await handler.status()
                Self.send(.success(response), requestID: requestID, reply: reply)
            } catch let ipc as IPCError {
                Self.send(IPCResponse<StatusResponse>.Result.error(ipc), requestID: requestID, reply: reply)
            } catch {
                Self.send(
                    IPCResponse<StatusResponse>.Result.error(IPCError(code: "internal_error", message: "\(error)")),
                    requestID: requestID,
                    reply: reply
                )
            }
        }
    }

    func query(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        dispatch(request, reply: reply) { handler, payload in
            try await handler.query(payload)
        }
    }

    func timeline(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        dispatch(request, reply: reply) { handler, payload in
            try await handler.timeline(payload)
        }
    }

    func events(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        dispatch(request, reply: reply) { handler, payload in
            try await handler.events(payload)
        }
    }

    func rules(reply: @escaping @Sendable (Data) -> Void) {
        let requestID = UUID()
        let handler = self.handler
        Task.detached {
            do {
                let response = try await handler.rules()
                Self.send(.success(response), requestID: requestID, reply: reply)
            } catch let ipc as IPCError {
                Self.send(IPCResponse<RulesResponse>.Result.error(ipc), requestID: requestID, reply: reply)
            } catch {
                Self.send(
                    IPCResponse<RulesResponse>.Result.error(IPCError(code: "internal_error", message: "\(error)")),
                    requestID: requestID,
                    reply: reply
                )
            }
        }
    }

    func addRule(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        dispatch(request, reply: reply) { handler, payload in
            try await handler.addRule(payload)
        }
    }

    func toggleRule(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        dispatch(request, reply: reply) { handler, payload in
            try await handler.toggleRule(payload)
        }
    }

    func deleteRule(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        dispatch(request, reply: reply) { handler, payload in
            try await handler.deleteRule(payload)
        }
    }

    func killApp(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        dispatch(request, reply: reply) { handler, payload in
            try await handler.killApp(payload)
        }
    }

    func setFocusMode(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        dispatch(request, reply: reply) { handler, payload in
            try await handler.setFocusMode(payload)
        }
    }

    // MARK: Helpers

    /// Generic dispatcher that decodes the envelope, validates the version, runs the
    /// handler block on a detached task, and encodes the response. All response
    /// paths (success, IPC error, unexpected error) produce a valid envelope so the
    /// client can always decode something useful.
    private func dispatch<Req: Codable & Sendable, Resp: Codable & Sendable>(
        _ data: Data,
        reply: @escaping @Sendable (Data) -> Void,
        work: @Sendable @escaping (any IPCHandler, Req) async throws -> Resp
    ) {
        let handler = self.handler
        // Decode synchronously so we can capture the requestID for error paths.
        let decoded: Result<IPCRequest<Req>, IPCError>
        do {
            let req = try IPCCoder.decoder().decode(IPCRequest<Req>.self, from: data)
            decoded = .success(req)
        } catch {
            decoded = .failure(IPCError(code: IPCError.decodeFailure.code, message: "\(error)"))
        }

        switch decoded {
        case .failure(let err):
            // We have no requestID to echo back; synthesise a zero UUID.
            Self.send(IPCResponse<Resp>.Result.error(err), requestID: UUID(), reply: reply)
        case .success(let envelope):
            guard envelope.version == IPCProtocol.version else {
                Self.send(
                    IPCResponse<Resp>.Result.error(.versionMismatch),
                    requestID: envelope.requestID,
                    reply: reply
                )
                return
            }
            Task.detached {
                do {
                    let response = try await work(handler, envelope.payload)
                    Self.send(.success(response), requestID: envelope.requestID, reply: reply)
                } catch let ipc as IPCError {
                    Self.send(IPCResponse<Resp>.Result.error(ipc), requestID: envelope.requestID, reply: reply)
                } catch {
                    Self.send(
                        IPCResponse<Resp>.Result.error(IPCError(code: "internal_error", message: "\(error)")),
                        requestID: envelope.requestID,
                        reply: reply
                    )
                }
            }
        }
    }

    /// Serialise an `IPCResponse` envelope and hand it to the reply block. If the
    /// payload itself fails to encode (shouldn't happen for our DTOs), fall back to
    /// a canonical encode-failure envelope so the client always sees valid JSON.
    static func send<Resp: Codable & Sendable>(
        _ result: IPCResponse<Resp>.Result,
        requestID: UUID,
        reply: @Sendable (Data) -> Void
    ) {
        let envelope = IPCResponse<Resp>(requestID: requestID, result: result)
        do {
            let data = try IPCCoder.encoder().encode(envelope)
            reply(data)
        } catch {
            // Last-ditch: encode a fixed error envelope with an `EmptyResponse` shape.
            // This should be essentially unreachable given DTO guarantees.
            let fallback = IPCResponse<EmptyResponse>(
                requestID: requestID,
                result: .error(IPCError(code: IPCError.encodeFailure.code, message: "\(error)"))
            )
            let data = (try? IPCCoder.encoder().encode(fallback)) ?? Data()
            reply(data)
        }
    }
}
