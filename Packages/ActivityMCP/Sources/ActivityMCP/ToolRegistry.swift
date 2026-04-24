import Foundation
import os

/// Thread-safe registry of MCP tools. Used by the protocol handler to service
/// `tools/list` and route `tools/call` invocations.
public final class ToolRegistry: @unchecked Sendable {
    private struct State {
        var order: [String] = []
        var tools: [String: ToolDefinition] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func register(_ tool: ToolDefinition) {
        state.withLock { s in
            if s.tools[tool.name] == nil {
                s.order.append(tool.name)
            }
            s.tools[tool.name] = tool
        }
    }

    public func list() -> [ToolDefinition] {
        state.withLock { s in
            s.order.compactMap { s.tools[$0] }
        }
    }

    /// Peek at a registered tool by name without dispatching it. The
    /// protocol handler uses this to pick the right rate-limit bucket
    /// (read vs. write) before invoking `call(name:arguments:)`.
    public func tool(named name: String) -> ToolDefinition? {
        state.withLock { $0.tools[name] }
    }

    public func setEnabled(name: String, enabled: Bool) {
        state.withLock { s in
            guard let existing = s.tools[name] else { return }
            s.tools[name] = existing.setting(enabled: enabled)
        }
    }

    /// Dispatches a `tools/call`. Returns `-32601` for unknown tools and
    /// `-32000` for disabled write tools; otherwise delegates to the handler
    /// and wraps thrown errors as `-32603` internal errors.
    public func call(name: String, arguments: JSONValue) async -> Result<JSONValue, JSONRPCError> {
        let tool = state.withLock { $0.tools[name] }
        guard let tool else {
            return .failure(.methodNotFound(name))
        }
        if tool.isWrite && !tool.enabled {
            return .failure(JSONRPCError(code: -32000, message: "write tool disabled: \(name)"))
        }
        if !tool.enabled {
            return .failure(JSONRPCError(code: -32000, message: "tool disabled: \(name)"))
        }
        do {
            let result = try await tool.handler(arguments)
            return .success(result)
        } catch let err as JSONRPCError {
            return .failure(err)
        } catch {
            return .failure(JSONRPCError(code: -32603, message: "\(error)"))
        }
    }
}
