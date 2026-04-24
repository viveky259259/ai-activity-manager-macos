import ArgumentParser
import Foundation
import ActivityIPC

extension AMCTL {
    public struct Timeline: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "timeline",
            abstract: "List timeline sessions in a time range.",
            discussion: """
            Example:
              amctl timeline --from 2025-04-01T00:00:00Z --to 2025-04-02T00:00:00Z
              amctl timeline --from 2025-04-01T00:00:00Z --to 2025-04-02T00:00:00Z --app com.apple.dt.Xcode --format json
            """
        )

        @Option(name: .long, help: "ISO8601 start timestamp.")
        public var from: String

        @Option(name: .long, help: "ISO8601 end timestamp.")
        public var to: String

        @Option(name: .long, help: "Filter by bundle ID (repeatable).")
        public var app: [String] = []

        @Option(name: .long, help: "Maximum number of sessions.")
        public var limit: Int?

        @Option(name: .long, help: "Output format: human|json|ndjson.")
        public var format: OutputFormat = .human

        @Flag(name: .long, help: "Emit Elapsed: N ms to stderr.")
        public var timing: Bool = false

        public init() {}

        public mutating func validate() throws {
            guard DateParsing.iso8601(from) != nil else {
                throw ValidationError("invalid --from: \(from)")
            }
            guard DateParsing.iso8601(to) != nil else {
                throw ValidationError("invalid --to: \(to)")
            }
        }

        public func run() async throws {
            guard let fromDate = DateParsing.iso8601(from),
                  let toDate = DateParsing.iso8601(to) else {
                throw ValidationError("invalid --from/--to")
            }
            let req = TimelineRequest(
                from: fromDate,
                to: toDate,
                bundleIDs: app.isEmpty ? nil : app,
                limit: limit
            )
            let client = ClientFactory.makeClient()
            let start = Date()
            do {
                let response = try await client.timeline(req)
                print(OutputFormatter.format(response, as: format))
                if timing { emitTiming(from: start) }
            } catch {
                if timing { emitTiming(from: start) }
                throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
            }
        }
    }
}
