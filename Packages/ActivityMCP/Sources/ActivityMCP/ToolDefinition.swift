import Foundation

/// One registered tool. `handler` is invoked with the parsed JSON arguments and
/// returns a JSON result that becomes the `tools/call` response body.
public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    public let enabled: Bool
    public let isWrite: Bool
    public let handler: @Sendable (JSONValue) async throws -> JSONValue

    public init(
        name: String,
        description: String,
        inputSchema: JSONValue,
        enabled: Bool,
        isWrite: Bool,
        handler: @escaping @Sendable (JSONValue) async throws -> JSONValue
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.enabled = enabled
        self.isWrite = isWrite
        self.handler = handler
    }

    /// Returns a copy with a different `enabled` flag; used by the registry to
    /// honor per-call toggles without touching the handler closure.
    public func setting(enabled newValue: Bool) -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: description,
            inputSchema: inputSchema,
            enabled: newValue,
            isWrite: isWrite,
            handler: handler
        )
    }
}
