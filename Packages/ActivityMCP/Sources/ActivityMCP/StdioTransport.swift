import Foundation

/// Newline-delimited JSON-RPC transport over stdin/stdout. One message per
/// line; the server writes one response line per non-notification request.
///
/// This is the default transport for Claude Desktop and most MCP hosts. It
/// uses `FileHandle.availableData` in a pump loop rather than the async
/// `bytes` sequence so it runs on Swift 6 strict-concurrency without spinning
/// up actor-isolation issues around `FileHandle`.
public final class StdioTransport: @unchecked Sendable {
    public let input: FileHandle
    public let output: FileHandle
    public let server: MCPServer

    public init(input: FileHandle = .standardInput, output: FileHandle = .standardOutput, server: MCPServer) {
        self.input = input
        self.output = output
        self.server = server
    }

    /// Blocks (as an async task) until stdin reaches EOF.
    public func run() async {
        var buffer = Data()
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)

            // Drain as many complete newline-terminated messages as we have.
            while let newlineIdx = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineIdx)
                buffer.removeSubrange(buffer.startIndex...newlineIdx)
                if lineData.isEmpty { continue }

                if let response = await server.handle(line: lineData) {
                    var out = response
                    out.append(0x0A)
                    try? output.write(contentsOf: out)
                }
            }
        }
    }
}
