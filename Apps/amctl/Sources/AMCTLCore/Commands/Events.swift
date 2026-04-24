import ArgumentParser
import Foundation
import ActivityCore
import ActivityIPC

extension AMCTL {
    public struct Events: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "events",
            abstract: "List captured activity events.",
            discussion: """
            Example:
              amctl events --limit 50
              amctl events --source frontmost --format ndjson
            """
        )

        @Option(name: .long, help: "Filter by bundle ID.")
        public var app: String?

        @Option(name: .long, help: "Filter by source (frontmost|idle|calendar|focusMode|screenshot|rule|mcp|cli).")
        public var source: String?

        @Option(name: .long, help: "Maximum number of events.")
        public var limit: Int = 100

        @Option(name: .long, help: "Period shorthand (today|7d|24h). Ignored if --from/--to given.")
        public var since: String = "today"

        @Option(name: .long, help: "ISO8601 start timestamp.")
        public var from: String?

        @Option(name: .long, help: "ISO8601 end timestamp.")
        public var to: String?

        @Option(name: .long, help: "Output format: human|json|ndjson.")
        public var format: OutputFormat = .human

        @Flag(name: .long, help: "Emit Elapsed: N ms to stderr.")
        public var timing: Bool = false

        public init() {}

        public func run() async throws {
            let range: DateInterval
            if let fromStr = from, let toStr = to {
                guard let f = DateParsing.iso8601(fromStr) else {
                    throw ValidationError("invalid --from: \(fromStr)")
                }
                guard let t = DateParsing.iso8601(toStr) else {
                    throw ValidationError("invalid --to: \(toStr)")
                }
                range = DateInterval(start: f, end: t)
            } else {
                guard let r = DateParsing.period(since) else {
                    throw ValidationError("invalid --since: \(since)")
                }
                range = r
            }

            let sourceFilter: ActivityEvent.Source?
            if let s = source {
                guard let parsed = ActivityEvent.Source(rawValue: s) else {
                    throw ValidationError("invalid --source: \(s)")
                }
                sourceFilter = parsed
            } else {
                sourceFilter = nil
            }

            let req = EventsRequest(
                from: range.start,
                to: range.end,
                source: sourceFilter,
                limit: limit
            )

            let client = ClientFactory.makeClient()
            let start = Date()
            do {
                let response = try await client.events(req)
                print(OutputFormatter.format(response, as: format))
                if timing { emitTiming(from: start) }
            } catch {
                if timing { emitTiming(from: start) }
                throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
            }
        }
    }
}
