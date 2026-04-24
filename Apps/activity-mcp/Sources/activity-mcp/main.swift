import Foundation
import ActivityCore
import ActivityIPC
import ActivityMCP

// IPCClient already conforms to ActivityClientProtocol (extension in the
// ActivityMCP module), so no separate adapter is needed. Keeping a typed
// `any ActivityClientProtocol` reference keeps the tool factories decoupled
// from the concrete transport.
let client: any ActivityClientProtocol = IPCClient(machServiceName: IPCProtocol.machServiceName)

let registry = ToolRegistry()

for tool in ReadTools.make(client: client) {
    registry.register(tool)
}

// Write tools ship disabled by default per PRD-08 section 5. The host opts in
// per tool via `ToolRegistry.setEnabled(name:enabled:)` at a later step.
for tool in WriteTools.make(client: client) {
    registry.register(tool)
}

let handler = DefaultMCPHandler(registry: registry)
let server = MCPServer(handler: handler)
let transport = StdioTransport(server: server)
await transport.run()
