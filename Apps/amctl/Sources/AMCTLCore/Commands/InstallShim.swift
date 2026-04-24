import ArgumentParser
import Foundation

extension AMCTL {
    public struct InstallShim: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "install-shim",
            abstract: "Install a symlink to the amctl binary in a $PATH directory.",
            discussion: """
            Example:
              amctl install-shim
              amctl install-shim --path /usr/local/bin
            """
        )

        @Option(name: .long, help: "Target directory for the symlink. Defaults to $HOME/.local/bin.")
        public var path: String?

        @Flag(name: .long, help: "Print the commands without executing them.")
        public var dryRun: Bool = false

        public init() {}

        public func run() async throws {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
            let target = path ?? (home + "/.local/bin")
            let source = "/Applications/ActivityManager.app/Contents/MacOS/amctl"
            let link = target + "/amctl"
            if dryRun {
                print("mkdir -p \(target)")
                print("ln -sf \(source) \(link)")
                return
            }
            let fm = FileManager.default
            if !fm.fileExists(atPath: target) {
                try fm.createDirectory(atPath: target, withIntermediateDirectories: true)
            }
            if fm.fileExists(atPath: link) {
                try fm.removeItem(atPath: link)
            }
            try fm.createSymbolicLink(atPath: link, withDestinationPath: source)
            print("Installed shim at \(link) -> \(source)")
        }
    }
}
