import ArgumentParser
import Foundation

extension AMCTL {
    public struct MCP: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "mcp",
            abstract: "Manage MCP server installation and tokens.",
            subcommands: [Install.self, Token.self, Doctor.self]
        )

        public init() {}

        public enum Target: String, ExpressibleByArgument, CaseIterable, Sendable {
            case claudeDesktop = "claude-desktop"
            case cursor
            case zed
        }

        public struct Install: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "install",
                abstract: "Install the MCP server config for a host.",
                discussion: "Example: amctl mcp install claude-desktop"
            )

            @Argument(help: "MCP host: claude-desktop|cursor|zed.")
            public var target: Target

            @Flag(name: .long, help: "Print the JSON snippet instead of writing it.")
            public var print: Bool = false

            public init() {}

            public func run() async throws {
                let snippet = Install.configSnippet(for: target)
                if self.print {
                    Swift.print(snippet)
                    return
                }
                Swift.print("Install \(target.rawValue) — writing config is not yet implemented; pass --print to see the snippet.")
            }

            static func configSnippet(for target: Target) -> String {
                switch target {
                case .claudeDesktop:
                    return #"""
                    {
                      "mcpServers": {
                        "activity-manager": {
                          "command": "/Applications/ActivityManager.app/Contents/MacOS/activity-mcp",
                          "args": []
                        }
                      }
                    }
                    """#
                case .cursor:
                    return #"""
                    {
                      "mcpServers": {
                        "activity-manager": {
                          "command": "/Applications/ActivityManager.app/Contents/MacOS/activity-mcp"
                        }
                      }
                    }
                    """#
                case .zed:
                    return #"""
                    {
                      "context_servers": {
                        "activity-manager": {
                          "command": {
                            "path": "/Applications/ActivityManager.app/Contents/MacOS/activity-mcp",
                            "args": []
                          }
                        }
                      }
                    }
                    """#
                }
            }
        }

        public struct Token: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "token",
                abstract: "Manage the MCP bearer token.",
                subcommands: [Rotate.self]
            )

            public init() {}

            public struct Rotate: AsyncParsableCommand {
                public static let configuration = CommandConfiguration(
                    commandName: "rotate",
                    abstract: "Rotate the MCP bearer token stored in Keychain.",
                    discussion: "Example: amctl mcp token rotate"
                )

                public init() {}

                public func run() async throws {
                    Swift.print("Token rotation is not yet implemented in this build.")
                }
            }
        }

        public struct Doctor: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "doctor",
                abstract: "Diagnose MCP wiring and permissions.",
                discussion: "Example: amctl mcp doctor"
            )

            public init() {}

            public func run() async throws {
                Swift.print("MCP doctor: OK (placeholder).")
            }
        }
    }
}
