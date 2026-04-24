import ArgumentParser
import Foundation

extension AMCTL {
    public struct Permissions: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "permissions",
            abstract: "Inspect or open TCC permissions.",
            subcommands: [Check.self, Open.self]
        )

        public init() {}

        public struct Check: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "check",
                abstract: "Print known TCC permission statuses.",
                discussion: "Example: amctl permissions check accessibility"
            )

            @Argument(help: "Permission name.")
            public var name: String

            public init() {}

            public func run() async throws {
                let client = ClientFactory.makeClient()
                do {
                    let status = try await client.status()
                    let value = status.permissions[name] ?? "unknown"
                    print("\(name): \(value)")
                } catch {
                    throw ExitCode(rawValue: ExitCodeMapper.code(for: error).rawValue)
                }
            }
        }

        public struct Open: AsyncParsableCommand {
            public static let configuration = CommandConfiguration(
                commandName: "open",
                abstract: "Open System Settings on the matching permission pane.",
                discussion: "Example: amctl permissions open accessibility"
            )

            @Argument(help: "Permission name (accessibility|screen|automation).")
            public var name: String

            public init() {}

            public func run() async throws {
                let url = Permissions.settingsURL(for: name)
                print("Open: \(url)")
            }
        }

        static func settingsURL(for name: String) -> String {
            switch name.lowercased() {
            case "accessibility":
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case "screen", "screenrecording", "screen-recording":
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            case "automation", "apple-events", "appleevents":
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
            default:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy"
            }
        }
    }
}
