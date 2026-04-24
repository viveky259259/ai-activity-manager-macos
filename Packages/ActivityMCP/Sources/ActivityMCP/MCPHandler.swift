import Foundation

/// Protocol for objects that respond to JSON-RPC requests. Decoupled from
/// `MCPServer` so tests can supply their own handler.
public protocol MCPHandler: Sendable {
    /// Handle a single request. Return `nil` for notifications (no id).
    func handle(request: JSONRPCRequest) async -> JSONRPCResponse?
}

/// Default `MCPHandler` that implements the MCP 2025-11 surface: `initialize`,
/// `tools/list`, `tools/call`, and ignores notifications.
///
/// Every `tools/call` is gated by a per-client sliding-window rate limiter
/// (60/min read, 10/min write per PRD §5) and recorded through the injected
/// `AuditLogger` so the host can surface a full audit trail.
public final class DefaultMCPHandler: MCPHandler, @unchecked Sendable {
    public let registry: ToolRegistry
    public let serverName: String
    public let serverVersion: String
    public let protocolVersion: String

    private let auditLogger: any AuditLogger
    private let readLimiter: RateLimiter
    private let writeLimiter: RateLimiter
    private let clientID: String

    public init(
        registry: ToolRegistry,
        serverName: String = "ActivityMCP",
        serverVersion: String = "0.1.0",
        protocolVersion: String = "2025-11-05",
        auditLogger: any AuditLogger = NullAuditLogger(),
        readLimiter: RateLimiter = RateLimiter(limit: 60, window: 60),
        writeLimiter: RateLimiter = RateLimiter(limit: 10, window: 60),
        clientID: String = "default"
    ) {
        self.registry = registry
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.protocolVersion = protocolVersion
        self.auditLogger = auditLogger
        self.readLimiter = readLimiter
        self.writeLimiter = writeLimiter
        self.clientID = clientID
    }

    public func handle(request: JSONRPCRequest) async -> JSONRPCResponse? {
        // Notifications have no id per JSON-RPC 2.0 and must not receive a response.
        guard let id = request.id else {
            return nil
        }

        switch request.method {
        case "initialize":
            return .init(id: id, result: .object([
                "protocolVersion": .string(protocolVersion),
                "capabilities": .object([
                    "tools": .object(["listChanged": .bool(false)]),
                ]),
                "serverInfo": .object([
                    "name": .string(serverName),
                    "version": .string(serverVersion),
                ]),
            ]))

        case "tools/list":
            let tools = registry.list().map { tool -> JSONValue in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                    "disabled": .bool(!tool.enabled),
                ])
            }
            return .init(id: id, result: .object(["tools": .array(tools)]))

        case "tools/call":
            guard let params = request.params,
                  let name = params["name"]?.stringValue else {
                return .init(id: id, error: .invalidParams)
            }
            let args = params["arguments"] ?? .object([:])

            // Pick the rate-limit bucket from the tool's write flag. Unknown
            // tools fall through the read bucket — the registry still returns
            // method-not-found below, so we preserve that error shape.
            let isWrite = registry.tool(named: name)?.isWrite ?? false
            let limiter = isWrite ? writeLimiter : readLimiter
            guard limiter.allow(clientID: clientID) else {
                await auditLogger.record(tool: name, params: args, outcome: "rate_limited")
                return .init(id: id, error: JSONRPCError(code: -32001, message: "rate limit exceeded"))
            }

            let result = await registry.call(name: name, arguments: args)
            switch result {
            case .success(let value):
                await auditLogger.record(tool: name, params: args, outcome: "succeeded")
                return .init(id: id, result: .object([
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string((try? jsonString(of: value)) ?? ""),
                        ])
                    ]),
                    "structuredContent": value,
                    "isError": .bool(false),
                ]))
            case .failure(let err):
                await auditLogger.record(tool: name, params: args, outcome: "error:\(err.code)")
                return .init(id: id, error: err)
            }

        default:
            return .init(id: id, error: .methodNotFound(request.method))
        }
    }

    private func jsonString(of value: JSONValue) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
