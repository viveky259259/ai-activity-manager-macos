import Foundation

/// Protocol for objects that respond to JSON-RPC requests. Decoupled from
/// `MCPServer` so tests can supply their own handler.
public protocol MCPHandler: Sendable {
    /// Handle a single request. Return `nil` for notifications (no id).
    func handle(request: JSONRPCRequest) async -> JSONRPCResponse?
}

/// Default `MCPHandler` that implements the MCP 2025-11 surface: `initialize`,
/// `tools/list`, `tools/call`, and ignores notifications.
public final class DefaultMCPHandler: MCPHandler, @unchecked Sendable {
    public let registry: ToolRegistry
    public let serverName: String
    public let serverVersion: String
    public let protocolVersion: String

    public init(
        registry: ToolRegistry,
        serverName: String = "ActivityMCP",
        serverVersion: String = "0.1.0",
        protocolVersion: String = "2025-11-05"
    ) {
        self.registry = registry
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.protocolVersion = protocolVersion
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
            let result = await registry.call(name: name, arguments: args)
            switch result {
            case .success(let value):
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
