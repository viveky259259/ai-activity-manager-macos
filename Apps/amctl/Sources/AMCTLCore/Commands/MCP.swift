import ArgumentParser
import Foundation
import ActivityIPC

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

            @Flag(name: .long, help: "Print the destination path that would be modified.")
            public var dryRun: Bool = false

            public init() {}

            public func run() async throws {
                if self.print {
                    Swift.print(Install.configSnippet(for: target))
                    return
                }
                let path = Install.configPath(for: target)
                if dryRun {
                    Swift.print("Would write \(target.rawValue) config to: \(path.path)")
                    return
                }
                let serverKey = Install.serverNamespace(for: target)
                let entryKey = "activity-manager"
                let entry = Install.entry(for: target)
                try Install.merge(
                    path: path,
                    serverKey: serverKey,
                    entryKey: entryKey,
                    entry: entry
                )
                Swift.print("Installed activity-manager into \(path.path).")
                Swift.print("Restart \(target.rawValue) to pick up the change.")
            }

            // MARK: - Paths

            static func configPath(for target: Target) -> URL {
                let home = FileManager.default.homeDirectoryForCurrentUser
                switch target {
                case .claudeDesktop:
                    return home
                        .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
                case .cursor:
                    return home.appendingPathComponent(".cursor/mcp.json")
                case .zed:
                    return home.appendingPathComponent(".config/zed/settings.json")
                }
            }

            static func serverNamespace(for target: Target) -> String {
                switch target {
                case .claudeDesktop, .cursor: return "mcpServers"
                case .zed: return "context_servers"
                }
            }

            // MARK: - Entry shapes

            static let binaryPath = "/Applications/ActivityManager.app/Contents/MacOS/activity-mcp"

            static func entry(for target: Target) -> [String: Any] {
                switch target {
                case .claudeDesktop:
                    return ["command": binaryPath, "args": [String]()]
                case .cursor:
                    return ["command": binaryPath]
                case .zed:
                    return ["command": ["path": binaryPath, "args": [String]()]]
                }
            }

            // MARK: - Merge

            /// Reads `path`, sets `<serverKey>.<entryKey> = entry`, and writes
            /// it back as pretty JSON. Creates parent directories as needed.
            /// Preserves any unrelated keys already present in the file.
            static func merge(
                path: URL,
                serverKey: String,
                entryKey: String,
                entry: [String: Any]
            ) throws {
                try FileManager.default.createDirectory(
                    at: path.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                var root: [String: Any] = [:]
                if let data = try? Data(contentsOf: path),
                   !data.isEmpty,
                   let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    root = decoded
                }

                var servers = (root[serverKey] as? [String: Any]) ?? [:]
                servers[entryKey] = entry
                root[serverKey] = servers

                let data = try JSONSerialization.data(
                    withJSONObject: root,
                    options: [.prettyPrinted, .sortedKeys]
                )
                try data.write(to: path, options: .atomic)
            }

            // MARK: - Printable snippet (used by --print)

            static func configSnippet(for target: Target) -> String {
                let root: [String: Any] = [
                    serverNamespace(for: target): ["activity-manager": entry(for: target)]
                ]
                let data = try? JSONSerialization.data(
                    withJSONObject: root,
                    options: [.prettyPrinted, .sortedKeys]
                )
                return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
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
                var failures = 0

                // 1. App bundle present?
                let appPath = "/Applications/ActivityManager.app"
                if FileManager.default.fileExists(atPath: appPath) {
                    Swift.print("✓ ActivityManager.app installed at \(appPath)")
                } else {
                    Swift.print("✗ ActivityManager.app NOT found at \(appPath)")
                    failures += 1
                }

                // 2. activity-mcp binary inside the bundle?
                let mcpBinary = "\(appPath)/Contents/MacOS/activity-mcp"
                if FileManager.default.isExecutableFile(atPath: mcpBinary) {
                    Swift.print("✓ activity-mcp binary present and executable")
                } else {
                    Swift.print("✗ activity-mcp binary missing or not executable: \(mcpBinary)")
                    failures += 1
                }

                // 3. IPC reachable? Try a status() call with a short deadline.
                let client = ClientFactory.makeClient()
                let deadline = Date().addingTimeInterval(2.0)
                do {
                    let task = Task<Void, Error> {
                        _ = try await client.status()
                    }
                    while !task.isCancelled, Date() < deadline {
                        if case .success = await task.result.map({ _ in () }) { break }
                        break
                    }
                    _ = try await client.status()
                    Swift.print("✓ IPC reachable (Mach service \(IPCProtocol.machServiceName))")
                } catch {
                    Swift.print("✗ IPC unreachable — is the ActivityManager app running? Error: \(error)")
                    failures += 1
                }

                // 4. MCP host configs present?
                for target in Target.allCases {
                    let path = Install.configPath(for: target)
                    if FileManager.default.fileExists(atPath: path.path) {
                        Swift.print("• \(target.rawValue) config: \(path.path)")
                    } else {
                        Swift.print("• \(target.rawValue) config: not installed (run `amctl mcp install \(target.rawValue)`)")
                    }
                }

                if failures > 0 {
                    Swift.print("")
                    Swift.print("\(failures) check(s) failed.")
                    throw ExitCode(rawValue: 1)
                }
            }
        }
    }
}
