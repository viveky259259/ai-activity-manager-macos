import ArgumentParser
import Foundation

extension AMCTL {
    public struct Tail: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "tail",
            abstract: "Stream events as they are captured (stub).",
            discussion: "Example: amctl tail --source frontmost"
        )

        @Option(name: .long, help: "Source filter (frontmost|idle|calendar|...).")
        public var source: String?

        public init() {}

        public func run() async throws {
            // The current IPC service does not yet expose a streaming endpoint.
            // This subcommand is wired up so the CLI surface is stable; the
            // underlying host support will land in a follow-up change.
            FileHandle.standardError.write(Data("tail: streaming not yet supported by host\n".utf8))
        }
    }
}
