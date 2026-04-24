import ArgumentParser
import Foundation

/// Top-level `amctl` command. Subcommands are registered as nested types on
/// the other files in this target.
public struct AMCTL: AsyncParsableCommand {
    /// Explicit async entry point. We expose this so the executable target can
    /// call a name that unambiguously resolves to the `AsyncParsableCommand`
    /// overload (otherwise the sync `ParsableCommand.main()` wins by default).
    public static func runAsync() async {
        await AMCTL.main(nil)
    }

    public static let configuration = CommandConfiguration(
        commandName: "amctl",
        abstract: "Command-line interface to the Activity Manager.",
        version: "0.1.0",
        subcommands: [
            Status.self,
            Query.self,
            Timeline.self,
            Events.self,
            Top.self,
            Rules.self,
            Actions.self,
            Tail.self,
            Permissions.self,
            InstallShim.self,
            MCP.self,
        ]
    )

    public init() {}
}
