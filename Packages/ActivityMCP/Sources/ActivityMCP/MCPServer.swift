import Foundation

/// Framing-agnostic JSON-RPC pump. Feed it one message at a time via
/// `handle(line:)`; returns the serialized response bytes or `nil` for
/// notifications.
public final class MCPServer: @unchecked Sendable {
    public let handler: any MCPHandler
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(handler: any MCPHandler) {
        self.handler = handler
        let enc = JSONEncoder()
        enc.outputFormatting = []
        self.encoder = enc
        self.decoder = JSONDecoder()
    }

    /// Parse one JSON-RPC envelope and produce the serialized response, or
    /// `nil` when the request was a notification. On parse failure this
    /// returns a `-32700` error envelope with a null id.
    public func handle(line: Data) async -> Data? {
        let request: JSONRPCRequest
        do {
            request = try decoder.decode(JSONRPCRequest.self, from: line)
        } catch {
            let response = JSONRPCResponse(id: .null, error: .parseError)
            return try? encoder.encode(response)
        }

        guard let response = await handler.handle(request: request) else {
            return nil
        }
        return try? encoder.encode(response)
    }
}
