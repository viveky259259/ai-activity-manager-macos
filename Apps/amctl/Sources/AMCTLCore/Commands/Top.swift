import ArgumentParser
import Foundation
import ActivityCore
import ActivityIPC

extension AMCTL {
    public struct Top: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "top",
            abstract: "Show top apps or URL hosts by duration.",
            discussion: """
            Example:
              amctl top --by app --since today
              amctl top --by host --since 7d
            """
        )

        public enum GroupBy: String, ExpressibleByArgument, CaseIterable, Sendable {
            case app
            case host
        }

        @Option(name: .long, help: "Group by app|host.")
        public var by: GroupBy = .app

        @Option(name: .long, help: "Period: today|7d|30d|24h.")
        public var since: String = "today"

        @Option(name: .long, help: "Output format: human|json|ndjson.")
        public var format: OutputFormat = .human

        @Flag(name: .long, help: "Emit Elapsed: N ms to stderr.")
        public var timing: Bool = false

        public init() {}

        public func run() async throws {
            guard let range = DateParsing.period(since) else {
                throw ValidationError("invalid --since: \(since)")
            }
            let client = ClientFactory.makeClient()
            let start = Date()
            do {
                let response = try await client.timeline(
                    TimelineRequest(from: range.start, to: range.end, bundleIDs: nil, limit: nil)
                )
                let aggregates = aggregate(response.sessions, by: by)
                emit(aggregates, format: format)
                if timing { emitTiming(from: start) }
            } catch {
                if timing { emitTiming(from: start) }
                throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
            }
        }

        func aggregate(_ sessions: [ActivitySession], by: GroupBy) -> [(String, TimeInterval)] {
            var totals: [String: TimeInterval] = [:]
            for s in sessions {
                switch (by, s.subject) {
                case (.app, .app(let bid, _)): totals[bid, default: 0] += s.duration
                case (.host, .url(let host, _)): totals[host, default: 0] += s.duration
                default: continue
                }
            }
            return totals.sorted { $0.value > $1.value }
        }

        private func emit(_ rows: [(String, TimeInterval)], format: OutputFormat) {
            switch format {
            case .human:
                if rows.isEmpty { print("No data."); return }
                let keyWidth = rows.map(\.0.count).max() ?? 0
                for (k, v) in rows {
                    let padded = k.padding(toLength: keyWidth, withPad: " ", startingAt: 0)
                    print("\(padded)  \(Int(v.rounded()))s")
                }
            case .json:
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                struct Row: Encodable { let key: String; let seconds: Double }
                struct Env: Encodable { let schema_version: Int; let rows: [Row] }
                let env = Env(
                    schema_version: OutputFormatter.schemaVersion,
                    rows: rows.map { Row(key: $0.0, seconds: $0.1) }
                )
                if let data = try? enc.encode(env), let s = String(data: data, encoding: .utf8) {
                    print(s)
                }
            case .ndjson:
                let enc = JSONEncoder()
                enc.outputFormatting = [.sortedKeys]
                struct Row: Encodable { let key: String; let seconds: Double }
                for (k, v) in rows {
                    if let data = try? enc.encode(Row(key: k, seconds: v)),
                       let s = String(data: data, encoding: .utf8) {
                        print(s)
                    }
                }
            }
        }
    }
}
