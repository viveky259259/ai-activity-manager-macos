import Foundation

/// Objective-C visible protocol exposed over `NSXPCConnection`.
///
/// All request/response payloads are JSON-encoded `Data` blobs wrapping
/// `IPCRequest<T>` / `IPCResponse<T>`. This keeps the Obj-C bridge trivial
/// while preserving Swift-native typing at the client and server boundary.
@objc public protocol ActivityIPCServiceProtocol {
    func status(reply: @escaping @Sendable (Data) -> Void)
    func query(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func timeline(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func events(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func rules(reply: @escaping @Sendable (Data) -> Void)
    func addRule(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func toggleRule(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func deleteRule(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func killApp(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func setFocusMode(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
}

/// Helper that produces a shared `NSXPCInterface` for the service protocol.
public enum ActivityIPCInterface {
    public static func make() -> NSXPCInterface {
        NSXPCInterface(with: ActivityIPCServiceProtocol.self)
    }
}
