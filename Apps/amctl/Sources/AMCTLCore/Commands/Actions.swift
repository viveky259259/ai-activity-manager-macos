import ArgumentParser
import Foundation
import ActivityCore
import ActivityIPC

extension AMCTL {
    public struct Actions: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "actions",
            abstract: "Execute a controlled action (kill, focus, ...).",
            subcommands: [
                Kill.self,
                Focus.self,
            ]
        )

        public init() {}

        public struct Kill: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "kill",
                abstract: "Request termination of an app by bundle ID.",
                discussion: "Example: amctl actions kill --bundle com.apple.Safari --yes"
            )

            @Option(name: .long, help: "Bundle ID of the target app.")
            public var bundle: String

            @Option(name: .long, help: "Termination strategy (politeQuit|forceQuit|signal).")
            public var strategy: String = "politeQuit"

            @Flag(name: .long, help: "Skip polite-quit; go straight to force.")
            public var force: Bool = false

            @Flag(name: .long, help: "Confirm the action without interactive prompt.")
            public var yes: Bool = false

            @Option(name: .long, help: "Output format: human|json|ndjson.")
            public var format: OutputFormat = .human

            public init() {}

            public func run() async throws {
                guard let strat = Action.KillStrategy(rawValue: strategy) else {
                    throw ValidationError("invalid --strategy: \(strategy)")
                }
                let client = ClientFactory.makeClient()
                do {
                    let response = try await client.killApp(
                        KillAppRequest(
                            bundleID: bundle,
                            strategy: strat,
                            force: force,
                            confirmed: yes
                        )
                    )
                    print(OutputFormatter.format(response, as: format))
                } catch {
                    throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
                }
            }
        }

        public struct Focus: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "focus",
                abstract: "Control the system focus mode.",
                subcommands: [Set.self]
            )

            public init() {}

            public struct Set: AsyncParsableCommand {
                public static let configuration = CommandConfiguration(
                    commandName: "set",
                    abstract: "Set the focus mode (empty to clear).",
                    discussion: "Example: amctl actions focus set \"Do Not Disturb\""
                )

                @Argument(help: "Focus mode name; empty string to clear.")
                public var mode: String

                public init() {}

                public func run() async throws {
                    let client = ClientFactory.makeClient()
                    do {
                        let request = SetFocusRequest(mode: mode.isEmpty ? nil : mode)
                        try await client.setFocusMode(request)
                        print("Focus mode set to \(mode.isEmpty ? "<cleared>" : mode).")
                    } catch {
                        throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
                    }
                }
            }
        }
    }
}
