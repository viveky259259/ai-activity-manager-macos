import Foundation
import Testing
@testable import ActivityMCP

@Suite("ToolRegistry")
struct ToolRegistryTests {
    @Test("list returns registered tools with disabled marker")
    func listEnumeratesTools() async throws {
        let registry = ToolRegistry()
        registry.register(ToolDefinition(
            name: "read_one",
            description: "read",
            inputSchema: .object(["type": .string("object")]),
            enabled: true,
            isWrite: false,
            handler: { _ in .object(["ok": .bool(true)]) }
        ))
        registry.register(ToolDefinition(
            name: "write_one",
            description: "write",
            inputSchema: .object(["type": .string("object")]),
            enabled: false,
            isWrite: true,
            handler: { _ in .object(["ok": .bool(true)]) }
        ))

        let listed = registry.list()
        #expect(listed.count == 2)
        let writeTool = try #require(listed.first(where: { $0.name == "write_one" }))
        #expect(writeTool.enabled == false)
        #expect(writeTool.isWrite == true)
    }

    @Test("call on unknown tool returns method-not-found -32601")
    func callUnknownTool() async throws {
        let registry = ToolRegistry()
        let response = await registry.call(name: "missing", arguments: .object([:]))
        switch response {
        case .failure(let err):
            #expect(err.code == -32601)
        case .success:
            Issue.record("expected failure for unknown tool")
        }
    }

    @Test("call on disabled write tool returns -32000")
    func callDisabledTool() async throws {
        let registry = ToolRegistry()
        registry.register(ToolDefinition(
            name: "kill_app",
            description: "kill",
            inputSchema: .object([:]),
            enabled: false,
            isWrite: true,
            handler: { _ in .object(["unreachable": .bool(true)]) }
        ))
        let response = await registry.call(name: "kill_app", arguments: .object([:]))
        switch response {
        case .failure(let err):
            #expect(err.code == -32000)
            #expect(err.message.contains("disabled"))
        case .success:
            Issue.record("disabled tool should not execute")
        }
    }

    @Test("call on enabled tool runs the handler")
    func callEnabledTool() async throws {
        let registry = ToolRegistry()
        registry.register(ToolDefinition(
            name: "ping",
            description: "ping",
            inputSchema: .object([:]),
            enabled: true,
            isWrite: false,
            handler: { args in .object(["echo": args]) }
        ))
        let response = await registry.call(name: "ping", arguments: .string("hi"))
        switch response {
        case .success(let val):
            guard case .object(let obj) = val else {
                Issue.record("expected object")
                return
            }
            #expect(obj["echo"] == .string("hi"))
        case .failure(let err):
            Issue.record("expected success, got \(err)")
        }
    }

    @Test("setEnabled toggles tool availability")
    func setEnabledToggles() async throws {
        let registry = ToolRegistry()
        registry.register(ToolDefinition(
            name: "toggle_me",
            description: "",
            inputSchema: .object([:]),
            enabled: false,
            isWrite: true,
            handler: { _ in .null }
        ))
        registry.setEnabled(name: "toggle_me", enabled: true)
        let listed = registry.list()
        #expect(listed.first?.enabled == true)
        let response = await registry.call(name: "toggle_me", arguments: .null)
        if case .failure = response { Issue.record("should be enabled now") }
    }
}
