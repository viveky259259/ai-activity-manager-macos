import ArgumentParser
import Foundation
import ActivityCore
import ActivityIPC

extension AMCTL {
    public struct Rules: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "rules",
            abstract: "Manage activity rules.",
            subcommands: [
                List.self,
                Add.self,
                Show.self,
                Enable.self,
                Disable.self,
                Delete.self,
                DryRun.self,
            ],
            defaultSubcommand: List.self
        )

        public init() {}

        public struct List: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "list",
                abstract: "List all rules.",
                discussion: "Example: amctl rules list --format json"
            )

            @Option(name: .long, help: "Output format: human|json|ndjson.")
            public var format: OutputFormat = .human

            public init() {}

            public func run() async throws {
                let client = ClientFactory.makeClient()
                do {
                    let response = try await client.rules()
                    print(OutputFormatter.format(response, as: format))
                } catch {
                    throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
                }
            }
        }

        public struct Add: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "add",
                abstract: "Add a rule from a natural-language description.",
                discussion: "Example: amctl rules add \"after 30m of Slack, suggest focus\""
            )

            @Argument(help: "Natural-language description of the rule.")
            public var nl: String

            @Option(name: .long, help: "Output format: human|json|ndjson.")
            public var format: OutputFormat = .human

            public init() {}

            public func run() async throws {
                let client = ClientFactory.makeClient()
                do {
                    let response = try await client.addRule(AddRuleRequest(nl: nl))
                    switch format {
                    case .human:
                        print("Added rule \(response.rule.id) — \(response.rule.name)")
                    case .json, .ndjson:
                        let enc = JSONEncoder()
                        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                        enc.dateEncodingStrategy = .iso8601
                        let env = AddEnvelope(
                            schema_version: OutputFormatter.schemaVersion,
                            id: response.rule.id.uuidString,
                            name: response.rule.name,
                            mode: response.rule.mode.rawValue
                        )
                        if let data = try? enc.encode(env), let s = String(data: data, encoding: .utf8) {
                            print(s)
                        }
                    }
                } catch {
                    throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
                }
            }

            private struct AddEnvelope: Encodable {
                let schema_version: Int
                let id: String
                let name: String
                let mode: String
            }
        }

        public struct Show: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "show",
                abstract: "Show a rule by ID.",
                discussion: "Example: amctl rules show <uuid>"
            )

            @Argument(help: "Rule UUID.")
            public var id: String

            public init() {}

            public func run() async throws {
                guard let uuid = UUID(uuidString: id) else {
                    throw ValidationError("invalid rule id: \(id)")
                }
                let client = ClientFactory.makeClient()
                do {
                    let response = try await client.rules()
                    guard let rule = response.rules.first(where: { $0.id == uuid }) else {
                        FileHandle.standardError.write(Data("rule not found: \(id)\n".utf8))
                        throw ExitCode(rawValue: AMCTLExitCode.usage.rawValue)
                    }
                    print("id:      \(rule.id)")
                    print("name:    \(rule.name)")
                    print("mode:    \(rule.mode.rawValue)")
                    print("trigger: \(rule.trigger.kind.rawValue)")
                    print("nl:      \(rule.nlSource)")
                } catch let e as ExitCode {
                    throw e
                } catch {
                    throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
                }
            }
        }

        public struct Enable: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "enable",
                abstract: "Enable a rule.",
                discussion: "Example: amctl rules enable <uuid>"
            )

            @Argument(help: "Rule UUID.")
            public var id: String

            public init() {}

            public func run() async throws {
                try await toggleRule(id: id, enabled: true)
            }
        }

        public struct Disable: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "disable",
                abstract: "Disable a rule.",
                discussion: "Example: amctl rules disable <uuid>"
            )

            @Argument(help: "Rule UUID.")
            public var id: String

            public init() {}

            public func run() async throws {
                try await toggleRule(id: id, enabled: false)
            }
        }

        public struct Delete: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "delete",
                abstract: "Delete a rule.",
                discussion: "Example: amctl rules delete <uuid>"
            )

            @Argument(help: "Rule UUID.")
            public var id: String

            public init() {}

            public func run() async throws {
                guard let uuid = UUID(uuidString: id) else {
                    throw ValidationError("invalid rule id: \(id)")
                }
                let client = ClientFactory.makeClient()
                do {
                    try await client.deleteRule(DeleteRuleRequest(id: uuid))
                    print("Deleted rule \(uuid)")
                } catch {
                    throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
                }
            }
        }

        public struct DryRun: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "dry-run",
                abstract: "Evaluate a rule over a time window without firing actions.",
                discussion: "Example: amctl rules dry-run <uuid> --since 7d"
            )

            @Argument(help: "Rule UUID.")
            public var id: String

            @Option(name: .long, help: "Period: today|7d|30d.")
            public var since: String = "today"

            public init() {}

            public func run() async throws {
                guard UUID(uuidString: id) != nil else {
                    throw ValidationError("invalid rule id: \(id)")
                }
                guard DateParsing.period(since) != nil else {
                    throw ValidationError("invalid --since: \(since)")
                }
                // Dry-run does not yet have a dedicated IPC endpoint; emit a
                // placeholder response so the command is still parseable and
                // the harness wiring is in place.
                print("Dry-run not yet supported by host (rule: \(id), period: \(since)).")
            }
        }
    }
}

private func toggleRule(id: String, enabled: Bool) async throws {
    guard let uuid = UUID(uuidString: id) else {
        throw ValidationError("invalid rule id: \(id)")
    }
    let client = ClientFactory.makeClient()
    do {
        try await client.toggleRule(ToggleRuleRequest(id: uuid, enabled: enabled))
        print("\(enabled ? "Enabled" : "Disabled") rule \(uuid)")
    } catch {
        throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
    }
}
