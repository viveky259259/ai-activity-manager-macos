import Foundation
import Testing
import ActivityCore
import ActivityIPC
@testable import ActivityMCP

@Suite("WriteTools")
struct WriteToolsTests {
    @Test("write tools start disabled")
    func writeToolsDisabledByDefault() async throws {
        let client = FakeActivityClient()
        let tools = WriteTools.make(client: client)
        for tool in tools {
            #expect(tool.isWrite == true)
            #expect(tool.enabled == false)
        }
    }

    @Test("kill_app disabled -> tools/call error via registry")
    func killAppDisabledReturnsError() async throws {
        let client = FakeActivityClient()
        let registry = ToolRegistry()
        for tool in WriteTools.make(client: client) { registry.register(tool) }

        let response = await registry.call(
            name: "kill_app",
            arguments: .object([
                "bundle_id": .string("com.apple.Safari"),
            ])
        )
        switch response {
        case .failure(let err):
            #expect(err.code == -32000)
        case .success:
            Issue.record("disabled tool should return error")
        }
        #expect(client.capturedKillAppRequest == nil)
    }

    @Test("kill_app when enabled calls IPC with right DTO")
    func killAppWhenEnabledCallsClient() async throws {
        let client = FakeActivityClient()
        let registry = ToolRegistry()
        for tool in WriteTools.make(client: client) { registry.register(tool) }
        registry.setEnabled(name: "kill_app", enabled: true)

        let response = await registry.call(
            name: "kill_app",
            arguments: .object([
                "bundle_id": .string("com.apple.Safari"),
                "strategy": .string("forceQuit"),
            ])
        )
        if case .failure(let err) = response {
            Issue.record("expected success, got \(err)")
        }
        let captured = try #require(client.capturedKillAppRequest)
        #expect(captured.bundleID == "com.apple.Safari")
        #expect(captured.strategy == .forceQuit)
    }

    @Test("propose_rule when enabled calls addRule")
    func proposeRuleCallsAddRule() async throws {
        let client = FakeActivityClient()
        let registry = ToolRegistry()
        for tool in WriteTools.make(client: client) { registry.register(tool) }
        registry.setEnabled(name: "propose_rule", enabled: true)

        let response = await registry.call(
            name: "propose_rule",
            arguments: .object(["nl_description": .string("when safari focused for 5m quit it")])
        )
        if case .failure(let err) = response {
            Issue.record("expected success, got \(err)")
        }
        let captured = try #require(client.capturedAddRuleRequest)
        #expect(captured.nl == "when safari focused for 5m quit it")
    }

    @Test("kill_app accepts pid and forwards it as Int32")
    func killAppWithPidForwards() async throws {
        let client = FakeActivityClient()
        let registry = ToolRegistry()
        for tool in WriteTools.make(client: client) { registry.register(tool) }
        registry.setEnabled(name: "kill_app", enabled: true)

        let response = await registry.call(
            name: "kill_app",
            arguments: .object([
                "pid": .int(4242),
                "strategy": .string("signal"),
            ])
        )
        if case .failure(let err) = response {
            Issue.record("expected success, got \(err)")
        }
        let captured = try #require(client.capturedKillAppRequest)
        #expect(captured.pid == 4242)
        #expect(captured.bundleID == nil)
        #expect(captured.strategy == .signal)
    }

    @Test("kill_app rejects when neither bundle_id nor pid is provided")
    func killAppRequiresTarget() async throws {
        let client = FakeActivityClient()
        let registry = ToolRegistry()
        for tool in WriteTools.make(client: client) { registry.register(tool) }
        registry.setEnabled(name: "kill_app", enabled: true)

        let response = await registry.call(name: "kill_app", arguments: .object([:]))
        switch response {
        case .failure(let err):
            #expect(err.code == JSONRPCError.invalidParams.code)
        case .success:
            Issue.record("expected invalidParams when target missing")
        }
        #expect(client.capturedKillAppRequest == nil)
    }

    @Test("kill_app rejects when both bundle_id and pid are provided")
    func killAppRejectsBothTargets() async throws {
        let client = FakeActivityClient()
        let registry = ToolRegistry()
        for tool in WriteTools.make(client: client) { registry.register(tool) }
        registry.setEnabled(name: "kill_app", enabled: true)

        let response = await registry.call(
            name: "kill_app",
            arguments: .object([
                "bundle_id": .string("com.apple.Safari"),
                "pid": .int(42),
            ])
        )
        switch response {
        case .failure(let err):
            #expect(err.code == JSONRPCError.invalidParams.code)
        case .success:
            Issue.record("expected invalidParams when both targets supplied")
        }
        #expect(client.capturedKillAppRequest == nil)
    }

    @Test("set_rule_enabled when enabled calls toggleRule")
    func setRuleEnabledCallsToggle() async throws {
        let client = FakeActivityClient()
        let registry = ToolRegistry()
        for tool in WriteTools.make(client: client) { registry.register(tool) }
        registry.setEnabled(name: "set_rule_enabled", enabled: true)

        let id = UUID()
        let response = await registry.call(
            name: "set_rule_enabled",
            arguments: .object([
                "rule_id": .string(id.uuidString),
                "enabled": .bool(true),
            ])
        )
        if case .failure(let err) = response {
            Issue.record("expected success, got \(err)")
        }
        let captured = try #require(client.capturedToggleRuleRequest)
        #expect(captured.id == id)
        #expect(captured.enabled == true)
    }
}
