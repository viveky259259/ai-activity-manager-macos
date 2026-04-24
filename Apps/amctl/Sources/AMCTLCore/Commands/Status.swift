import ArgumentParser
import Foundation
import ActivityIPC

extension AMCTL {
    public struct Status: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show the Activity Manager host status.",
            discussion: """
            Example:
              amctl status
              amctl status --format json
            """
        )

        @Option(name: .long, help: "Output format: human|json|ndjson.")
        public var format: OutputFormat = .human

        @Flag(name: .long, help: "Emit Elapsed: N ms to stderr.")
        public var timing: Bool = false

        public init() {}

        public func run() async throws {
            let client = ClientFactory.makeClient()
            let start = Date()
            do {
                let response = try await client.status()
                print(OutputFormatter.format(response, as: format))
                if timing { emitTiming(from: start) }
            } catch {
                if timing { emitTiming(from: start) }
                throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
            }
        }
    }
}

func emitTiming(from start: Date) {
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    FileHandle.standardError.write(Data("Elapsed: \(ms) ms\n".utf8))
}
