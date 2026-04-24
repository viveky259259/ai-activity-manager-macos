# PRD-06 — ActivityIPC

**Status:** proposed · **Depends on:** PRD-01 · **Blocks:** PRD-07, PRD-08

## 1. Purpose

Provide a named XPC Mach service so `amctl` and `activity-mcp` can talk to the running menu-bar app. Single source of truth: both UI and IPC clients invoke the same `ActivityCore` use cases.

## 2. Service identity

- Mach service name: `com.yourco.ActivityManager.ipc`.
- Registered by the app via `NSXPCListener`.
- Client-side via `NSXPCConnection(machServiceName:options:[])`.
- Codesign peer check (`SecCodeCheckValidity`) gates accepted connections.

## 3. Protocol

Typed `@objc` protocol returning Codable DTOs encoded as JSON (over Data).

```swift
@objc public protocol ActivityIPCService {
    // Read
    func status(reply: @escaping (Data) -> Void)
    func query(_ request: Data, reply: @escaping (Data) -> Void)
    func timeline(_ request: Data, reply: @escaping (Data) -> Void)
    func events(_ request: Data, reply: @escaping (Data) -> Void)
    func rules(_ request: Data, reply: @escaping (Data) -> Void)

    // Write
    func addRule(_ request: Data, reply: @escaping (Data) -> Void)
    func toggleRule(_ request: Data, reply: @escaping (Data) -> Void)
    func deleteRule(_ request: Data, reply: @escaping (Data) -> Void)
    func killApp(_ request: Data, reply: @escaping (Data) -> Void)
    func setFocusMode(_ request: Data, reply: @escaping (Data) -> Void)

    // Streaming
    func tail(_ request: Data, streamHandle: NSXPCListenerEndpoint, reply: @escaping (Data) -> Void)
}
```

Envelopes:

```swift
public struct IPCRequest<T: Codable & Sendable>: Codable, Sendable {
    public let version: Int              // protocol version
    public let requestID: UUID
    public let payload: T
}

public struct IPCResponse<T: Codable & Sendable>: Codable, Sendable {
    public let requestID: UUID
    public let result: Result
    public enum Result: Codable, Sendable {
        case success(T)
        case error(IPCError)
    }
}

public struct IPCError: Codable, Sendable {
    public let code: String
    public let message: String
}
```

## 4. DTOs

Each use case has a typed request/response DTO in `ActivityIPC/DTOs/`:

- `QueryRequest/Response`
- `TimelineRequest/Response`
- `RulesResponse`
- `AddRuleRequest/Response`
- `KillAppRequest/Response`
- `StatusResponse`

## 5. Server harness

```swift
public final class IPCServer {
    public init(useCases: UseCaseContainer)
    public func start() throws
    public func stop()
}
```

- Validates connecting process via codesign (`SecCodeCheckValidity` with designated requirement).
- Logs every request to `OSLog` subsystem `com.yourco.ActivityManager.ipc`.
- Dispatches to `ActivityCore` use cases.

## 6. Client

```swift
public final class IPCClient {
    public init(machServiceName: String = "com.yourco.ActivityManager.ipc")
    public func status() async throws -> StatusResponse
    public func query(_ req: QueryRequest) async throws -> QueryResponse
    public func timeline(_ req: TimelineRequest) async throws -> TimelineResponse
    public func rules() async throws -> RulesResponse
    public func addRule(_ req: AddRuleRequest) async throws -> AddRuleResponse
    public func toggleRule(_ req: ToggleRuleRequest) async throws
    public func killApp(_ req: KillAppRequest) async throws -> KillAppResponse
    public func tail() -> AsyncThrowingStream<ActivityEvent, Error>
}
```

## 7. Streaming

`tail` uses a second `NSXPCListenerEndpoint` vended by the client; the server pushes events to the client-side listener. `AsyncThrowingStream` wraps the push callbacks.

## 8. Testing strategy

- Pure unit tests for envelope encoding/decoding.
- Integration tests for client↔server round-trip using anonymous XPC (`NSXPCListener.anonymous()`), no Mach service registration required.
- Codesign peer check is mocked in integration tests; real check is end-to-end verified manually (requires a signed build).

## 9. Acceptance

- [ ] Envelopes round-trip without loss for all DTOs.
- [ ] Anonymous XPC integration test: `status()` returns expected response.
- [ ] Unknown protocol version in request → server returns `IPCError(code: "version_mismatch")`.
- [ ] Streaming `tail` delivers 100 events in order.

## 10. Out of scope

- Authentication tokens (not needed for XPC; codesign is the fence).
- Cross-machine IPC.
