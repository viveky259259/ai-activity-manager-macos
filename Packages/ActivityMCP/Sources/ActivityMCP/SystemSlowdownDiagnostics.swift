import Foundation
import ActivityCore
import ActivityIPC

public struct SystemSlowdownDiagnosticsResponse: Codable, Sendable, Equatable {
    public let findings: [SystemSlowdownFinding]
    public let sampledAt: Date
    public let processSampledAt: Date?
    public let launchdSampledAt: Date?
    public let systemMemoryUsedBytes: UInt64?
    public let systemMemoryTotalBytes: UInt64?
    public let explanation: String

    public init(
        findings: [SystemSlowdownFinding],
        sampledAt: Date = Date(),
        processSampledAt: Date?,
        launchdSampledAt: Date?,
        systemMemoryUsedBytes: UInt64?,
        systemMemoryTotalBytes: UInt64?,
        explanation: String
    ) {
        self.findings = findings
        self.sampledAt = sampledAt
        self.processSampledAt = processSampledAt
        self.launchdSampledAt = launchdSampledAt
        self.systemMemoryUsedBytes = systemMemoryUsedBytes
        self.systemMemoryTotalBytes = systemMemoryTotalBytes
        self.explanation = explanation
    }
}

public struct SystemSlowdownFinding: Codable, Sendable, Equatable {
    public let kind: String
    public let severity: String
    public let score: Double
    public let title: String
    public let explanation: String
    public let evidence: [String]
    public let suggestedNextStep: String
    public let process: ProcessSnapshot?
    public let launchd: LaunchdRestartStormFinding?

    public init(
        kind: String,
        severity: String,
        score: Double,
        title: String,
        explanation: String,
        evidence: [String],
        suggestedNextStep: String,
        process: ProcessSnapshot?,
        launchd: LaunchdRestartStormFinding?
    ) {
        self.kind = kind
        self.severity = severity
        self.score = score
        self.title = title
        self.explanation = explanation
        self.evidence = evidence
        self.suggestedNextStep = suggestedNextStep
        self.process = process
        self.launchd = launchd
    }
}

public enum SystemSlowdownDiagnostics {
    public static func makeResponse(
        cpuProcesses: ProcessesPage,
        memoryProcesses: ProcessesPage,
        launchdStorms: LaunchdRestartStormsResponse?,
        minCPUPercent: Double,
        minMemoryBytes: UInt64,
        limit: Int
    ) -> SystemSlowdownDiagnosticsResponse {
        let effectiveLimit = max(1, min(limit, 50))
        let processes = mergeProcesses(cpuProcesses.processes, memoryProcesses.processes)
        var findings = processFindings(
            from: processes,
            minCPUPercent: minCPUPercent,
            minMemoryBytes: minMemoryBytes
        )

        if let launchdStorms {
            findings.append(contentsOf: launchdStorms.findings.map(launchdFinding))
        }

        findings.sort { lhs, rhs in
            if lhs.severityRank == rhs.severityRank {
                return lhs.score == rhs.score ? lhs.title < rhs.title : lhs.score > rhs.score
            }
            return lhs.severityRank > rhs.severityRank
        }

        let explanation: String
        if findings.isEmpty {
            explanation = "No high CPU, high memory, or launchd restart-storm suspects crossed the configured thresholds."
        } else {
            explanation = "Ranked suspects combine live process pressure with launchd restart-loop signals so an AI client can debug slowdown without regenerating macOS shell commands on every turn."
        }

        return SystemSlowdownDiagnosticsResponse(
            findings: Array(findings.prefix(effectiveLimit)),
            processSampledAt: [cpuProcesses.sampledAt, memoryProcesses.sampledAt].max(),
            launchdSampledAt: launchdStorms?.sampledAt,
            systemMemoryUsedBytes: cpuProcesses.systemMemoryUsedBytes ?? memoryProcesses.systemMemoryUsedBytes,
            systemMemoryTotalBytes: cpuProcesses.systemMemoryTotalBytes ?? memoryProcesses.systemMemoryTotalBytes,
            explanation: explanation
        )
    }

    private static func mergeProcesses(_ groups: [ProcessSnapshot]...) -> [ProcessSnapshot] {
        var byPID: [Int32: ProcessSnapshot] = [:]
        for group in groups {
            for process in group {
                if let existing = byPID[process.pid] {
                    byPID[process.pid] = process.cpuPercent >= existing.cpuPercent ? process : existing
                } else {
                    byPID[process.pid] = process
                }
            }
        }
        return Array(byPID.values)
    }

    private static func processFindings(
        from processes: [ProcessSnapshot],
        minCPUPercent: Double,
        minMemoryBytes: UInt64
    ) -> [SystemSlowdownFinding] {
        processes.compactMap { process in
            let highCPU = process.cpuPercent >= minCPUPercent
            let highMemory = process.memoryBytes >= minMemoryBytes
            guard highCPU || highMemory else { return nil }

            let cpuScore = process.cpuPercent
            let memoryScore = Double(process.memoryBytes) / 1_073_741_824 * 10
            let score = cpuScore + memoryScore
            let severity: String
            if process.cpuPercent >= 80 || process.memoryBytes >= 4_294_967_296 {
                severity = "high"
            } else if process.cpuPercent >= 40 || process.memoryBytes >= 2_147_483_648 {
                severity = "medium"
            } else {
                severity = "low"
            }

            let evidence = [
                String(format: "CPU %.1f%%", process.cpuPercent),
                "memory \(process.memoryBytes) bytes",
                "pid \(process.pid)",
                process.isFrontmost ? "frontmost app" : nil,
                process.isRestricted ? "restricted process metadata" : nil,
                process.category.map { "category \($0)" },
            ].compactMap { $0 }

            let reason: String
            switch (highCPU, highMemory) {
            case (true, true):
                reason = "Process is above both CPU and memory thresholds."
            case (true, false):
                reason = "Process is above the CPU threshold and may be contributing to input lag."
            case (false, true):
                reason = "Process is above the memory threshold and may be increasing system pressure."
            case (false, false):
                reason = "Process crossed a configured threshold."
            }

            return SystemSlowdownFinding(
                kind: "process",
                severity: severity,
                score: score,
                title: "\(process.name) (\(process.pid))",
                explanation: reason,
                evidence: evidence,
                suggestedNextStep: "Inspect recent activity for this app before closing it; use kill_app only after user confirmation.",
                process: process,
                launchd: nil
            )
        }
    }

    private static func launchdFinding(_ storm: LaunchdRestartStormFinding) -> SystemSlowdownFinding {
        let severityScore: Double
        switch storm.severity {
        case "high": severityScore = 1_000
        case "medium": severityScore = 500
        default: severityScore = 100
        }
        let score = severityScore + Double(storm.runs)
        let evidence = [
            "runs \(storm.runs)",
            storm.lastExitCode.map { "last exit code \($0)" },
            storm.immediateReason.map { "immediate reason \($0)" },
            "KeepAlive \(storm.keepAlive)",
            storm.throttleInterval.map { "ThrottleInterval \($0)" },
            storm.plistPath,
        ].compactMap { $0 }

        return SystemSlowdownFinding(
            kind: "launchd_restart_storm",
            severity: storm.severity,
            score: score,
            title: storm.label,
            explanation: storm.explanation,
            evidence: evidence,
            suggestedNextStep: "Inspect the plist and stderr; boot out or fix the job config if it is repeatedly exiting.",
            process: nil,
            launchd: storm
        )
    }
}

private extension SystemSlowdownFinding {
    var severityRank: Int {
        switch severity {
        case "high": return 3
        case "medium": return 2
        default: return 1
        }
    }
}
