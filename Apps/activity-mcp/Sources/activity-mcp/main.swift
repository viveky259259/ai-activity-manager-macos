import Foundation
import ActivityCore
import ActivityIPC
import ActivityMCP

// Bumped on every tagged release; embedded so package managers (Homebrew test,
// MCP host doctor commands, support emails) can probe without reading XPC.
let activityMCPVersion = "1.0.0"

if CommandLine.arguments.dropFirst().contains(where: { $0 == "--version" || $0 == "-v" }) {
    print(activityMCPVersion)
    exit(0)
}

if CommandLine.arguments.dropFirst().contains(where: { $0 == "--help" || $0 == "-h" }) {
    print("""
    activity-mcp \(activityMCPVersion)
    Stdio MCP server exposing your local activity timeline.

    Usage: activity-mcp                # speak MCP over stdio
           activity-mcp --version      # print version and exit
           activity-mcp --help         # this message
    """)
    exit(0)
}

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
