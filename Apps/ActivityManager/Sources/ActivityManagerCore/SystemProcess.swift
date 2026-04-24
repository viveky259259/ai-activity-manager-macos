import Foundation

/// A running OS process as shown in the Activity-Monitor-style Processes window.
///
/// Distinct from ``RunningApp`` (GUI-registered apps from `NSWorkspace`) — this
/// covers every process visible to the caller, including daemons and helpers.
public struct SystemProcess: Identifiable, Hashable, Sendable {
    public let id: Int32           // pid
    public let name: String        // best display name (localized app name if
                                   // a bundle ID maps, else `comm` from BSD info)
    public let executablePath: String
    public let bundleID: String?   // present when the PID is a registered app
    public let user: String        // pw_name, falling back to uid
    public let cpuPercent: Double  // rolling % (per-core aggregated)
    public let memoryBytes: UInt64 // phys_footprint; 0 when restricted
    public let threads: Int
    /// True when the OS denied task-read permission for this PID — values for
    /// cpu/memory/threads are unavailable and should render as "—".
    public let isRestricted: Bool

    public init(
        id: Int32,
        name: String,
        executablePath: String,
        bundleID: String?,
        user: String,
        cpuPercent: Double,
        memoryBytes: UInt64,
        threads: Int,
        isRestricted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.bundleID = bundleID
        self.user = user
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.threads = threads
        self.isRestricted = isRestricted
    }
}

/// Single raw observation of a process. CPU is reported as a cumulative
/// nanosecond counter; the monitor converts that into a % over wall-clock time.
public struct ProcessRawSample: Hashable, Sendable {
    public let pid: Int32
    public let name: String
    public let executablePath: String
    public let bundleID: String?
    public let user: String
    public let cpuNanos: UInt64
    public let memoryBytes: UInt64
    public let threads: Int
    public let isRestricted: Bool

    public init(
        pid: Int32,
        name: String,
        executablePath: String,
        bundleID: String?,
        user: String,
        cpuNanos: UInt64,
        memoryBytes: UInt64,
        threads: Int,
        isRestricted: Bool = false
    ) {
        self.pid = pid
        self.name = name
        self.executablePath = executablePath
        self.bundleID = bundleID
        self.user = user
        self.cpuNanos = cpuNanos
        self.memoryBytes = memoryBytes
        self.threads = threads
        self.isRestricted = isRestricted
    }
}

/// Enumerates every visible process. The live implementation uses libproc;
/// tests inject a fake.
public protocol SystemProcessSampler: Sendable {
    func capture() -> [ProcessRawSample]
}
