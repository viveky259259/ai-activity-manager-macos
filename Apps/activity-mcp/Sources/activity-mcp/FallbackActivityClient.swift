import Foundation
import ActivityCore
import ActivityIPC
import ActivityMCP

/// Keeps timeline/rule/action tools on the app daemon, but lets the read-only
/// `list_processes` tool work in local development when the unsigned app
/// bundle cannot register its Mach service.
final class FallbackActivityClient: ActivityClientProtocol, @unchecked Sendable {
    private let primary: any ActivityClientProtocol
    private let localProcesses = LocalProcessSnapshotSource()

    init(primary: any ActivityClientProtocol) {
        self.primary = primary
    }

    func status() async throws -> StatusResponse {
        try await primary.status()
    }

    func timeline(_ request: TimelineRequest) async throws -> TimelineResponse {
        try await primary.timeline(request)
    }

    func events(_ request: EventsRequest) async throws -> EventsResponse {
        try await primary.events(request)
    }

    func rules() async throws -> RulesResponse {
        try await primary.rules()
    }

    func addRule(_ request: AddRuleRequest) async throws -> AddRuleResponse {
        try await primary.addRule(request)
    }

    func toggleRule(_ request: ToggleRuleRequest) async throws {
        try await primary.toggleRule(request)
    }

    func killApp(_ request: KillAppRequest) async throws -> KillAppResponse {
        try await primary.killApp(request)
    }

    func setFocusMode(_ request: SetFocusRequest) async throws {
        try await primary.setFocusMode(request)
    }

    func listProcesses(_ request: ProcessesQuery) async throws -> ProcessesPage {
        do {
            return try await primary.listProcesses(request)
        } catch {
            return localProcesses.snapshot(query: request)
        }
    }
}

private struct LocalProcessSnapshotSource: Sendable {
    func snapshot(query: ProcessesQuery) -> ProcessesPage {
        let snapshots = sample()
        let filtered = ProcessesQueryApplier.apply(query, to: snapshots)
        return ProcessesPage(
            processes: filtered,
            systemMemoryUsedBytes: nil,
            systemMemoryTotalBytes: nil,
            sampledAt: Date()
        )
    }

    private func sample() -> [ProcessSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,user,%cpu,rss,comm"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n")
            .dropFirst()
            .compactMap(parseProcessLine)
    }

    private func parseProcessLine(_ raw: Substring) -> ProcessSnapshot? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        let parts = line.split(maxSplits: 4, whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 5,
              let pid = Int32(parts[0]),
              let cpu = Double(parts[2]),
              let rssKilobytes = UInt64(parts[3]) else {
            return nil
        }

        let command = String(parts[4])
        let name = URL(fileURLWithPath: command).lastPathComponent
        return ProcessSnapshot(
            pid: pid,
            bundleID: nil,
            name: name.isEmpty ? command : name,
            user: String(parts[1]),
            memoryBytes: rssKilobytes * 1024,
            cpuPercent: cpu,
            threads: 0,
            isFrontmost: false,
            isRestricted: false
        )
    }
}
