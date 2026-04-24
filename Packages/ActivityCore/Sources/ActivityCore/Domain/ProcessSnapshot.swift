import Foundation

/// A moment-in-time record of a running OS process. Sourced from the
/// system process sampler and carried across IPC so external agents (MCP,
/// CLI) can reason about live system state without having to poke libproc
/// themselves.
public struct ProcessSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: Int32 { pid }

    public let pid: Int32
    public let bundleID: String?
    public let name: String
    public let user: String
    public let memoryBytes: UInt64
    public let cpuPercent: Double
    public let threads: Int
    public let isFrontmost: Bool
    public let isRestricted: Bool
    /// Optional category tag (e.g. "browser") attached at query time from
    /// a static catalog. Nil if the bundle ID is unmapped or absent.
    public let category: String?

    public init(
        pid: Int32,
        bundleID: String?,
        name: String,
        user: String,
        memoryBytes: UInt64,
        cpuPercent: Double,
        threads: Int,
        isFrontmost: Bool,
        isRestricted: Bool,
        category: String? = nil
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.user = user
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.threads = threads
        self.isFrontmost = isFrontmost
        self.isRestricted = isRestricted
        self.category = category
    }
}
