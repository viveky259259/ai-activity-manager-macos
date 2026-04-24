import ArgumentParser
import Foundation
import ActivityIPC

extension AMCTL {
    public struct Query: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "query",
            abstract: "Ask a natural-language question of the timeline.",
            discussion: """
            Example:
              amctl query "how much Xcode today?"
              amctl query "meetings yesterday" --since 2d
            """
        )

        @Argument(help: "Natural-language question.")
        public var question: String

        @Option(name: .long, help: "Period to consider: today|7d|30d|24h.")
        public var since: String = "today"

        @Option(name: .long, help: "Output format: human|json|ndjson.")
        public var format: OutputFormat = .human

        @Flag(name: .long, help: "Emit Elapsed: N ms to stderr.")
        public var timing: Bool = false

        public init() {}

        public func run() async throws {
            guard let range = DateParsing.period(since) else {
                throw ValidationError("invalid --since value: \(since)")
            }
            let client = ClientFactory.makeClient()
            let start = Date()
            do {
                let response = try await client.query(QueryRequest(question: question, range: range))
                switch format {
                case .human:
                    print(response.answer)
                case .json, .ndjson:
                    let enc = JSONEncoder()
                    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    enc.dateEncodingStrategy = .iso8601
                    let envelope = QueryEnvelope(
                        schema_version: OutputFormatter.schemaVersion,
                        answer: response.answer,
                        provider: response.provider,
                        took_ms: response.tookMillis,
                        cited_session_ids: response.cited.map { $0.id.uuidString }
                    )
                    let data = try enc.encode(envelope)
                    print(String(data: data, encoding: .utf8) ?? "")
                }
                if timing { emitTiming(from: start) }
            } catch {
                if timing { emitTiming(from: start) }
                throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
            }
        }

        private struct QueryEnvelope: Encodable {
            let schema_version: Int
            let answer: String
            let provider: String
            let took_ms: Int
            let cited_session_ids: [String]
        }
    }
}
