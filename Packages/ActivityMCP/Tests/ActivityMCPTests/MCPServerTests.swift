import Foundation
import Testing
import ActivityIPC
@testable import ActivityMCP

@Suite("MCPServer")
struct MCPServerTests {
    private func makeServer(client: FakeActivityClient = FakeActivityClient()) -> MCPServer {
        let registry = ToolRegistry()
        for t in ReadTools.make(client: client) { registry.register(t) }
        for t in WriteTools.make(client: client) { registry.register(t) }
        let handler = DefaultMCPHandler(registry: registry)
        return MCPServer(handler: handler)
    }

    @Test("initialize returns protocolVersion + capabilities")
    func initializeHandshake() async throws {
        let server = makeServer()
        let req = #"""
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-05"}}
        """#
        let responseData = try #require(await server.handle(line: Data(req.utf8)))
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
        #expect(decoded.id == .int(1))

        guard case .some(.object(let obj)) = decoded.result else {
            Issue.record("expected object result")
            return
        }
        #expect(obj["protocolVersion"] != nil)
        #expect(obj["capabilities"] != nil)
    }

    @Test("tools/list returns registered tools")
    func toolsList() async throws {
        let server = makeServer()
        let req = #"""
        {"jsonrpc":"2.0","id":2,"method":"tools/list"}
        """#
        let responseData = try #require(await server.handle(line: Data(req.utf8)))
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
        guard case .some(.object(let obj)) = decoded.result,
              case .array(let tools) = obj["tools"] else {
            Issue.record("expected tools array")
            return
        }
        // 12 read + 4 write = 16 total
        #expect(tools.count == 16)
    }

    @Test("tools/call dispatches to registry")
    func toolsCallDispatches() async throws {
        let client = FakeActivityClient()
        client.setStatus(StatusResponse(
            sources: ["frontmost"],
            capturedEventCount: 7,
            actionsEnabled: false,
            permissions: [:]
        ))
        let server = makeServer(client: client)
        let req = #"""
        {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"current_activity","arguments":{}}}
        """#
        let responseData = try #require(await server.handle(line: Data(req.utf8)))
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
        #expect(decoded.id == .int(3))
        #expect(decoded.error == nil)
    }

    @Test("notification (no id) yields no response")
    func notificationReturnsNil() async throws {
        let server = makeServer()
        let req = #"""
        {"jsonrpc":"2.0","method":"notifications/initialized"}
        """#
        let resp = await server.handle(line: Data(req.utf8))
        #expect(resp == nil)
    }
}
