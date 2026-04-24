import Foundation

/// Records every MCP tool invocation so the app can surface a full audit
/// trail (per PRD §5 — "each MCP call creates an ActivityEvent").
public protocol AuditLogger: Sendable {
    func record(tool: String, params: JSONValue, outcome: String) async
}

public struct NullAuditLogger: AuditLogger {
    public init() {}
    public func record(tool: String, params: JSONValue, outcome: String) async {}
}
