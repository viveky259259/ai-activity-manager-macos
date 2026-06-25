import Foundation

public struct LaunchdRestartStormsResponse: Codable, Sendable, Equatable {
    public let findings: [LaunchdRestartStormFinding]
    public let sampledAt: Date

    public init(findings: [LaunchdRestartStormFinding], sampledAt: Date = Date()) {
        self.findings = findings
        self.sampledAt = sampledAt
    }
}

public struct LaunchdRestartStormFinding: Codable, Sendable, Equatable {
    public let label: String
    public let domain: String
    public let plistPath: String
    public let program: String?
    public let arguments: [String]
    public let pid: Int32?
    public let runs: Int
    public let lastExitCode: String?
    public let immediateReason: String?
    public let keepAlive: Bool
    public let runAtLoad: Bool
    public let throttleInterval: Int?
    public let stdoutPath: String?
    public let stderrPath: String?
    public let recentStderr: String?
    public let severity: String
    public let explanation: String

    public init(
        label: String,
        domain: String,
        plistPath: String,
        program: String?,
        arguments: [String],
        pid: Int32?,
        runs: Int,
        lastExitCode: String?,
        immediateReason: String?,
        keepAlive: Bool,
        runAtLoad: Bool,
        throttleInterval: Int?,
        stdoutPath: String?,
        stderrPath: String?,
        recentStderr: String?,
        severity: String,
        explanation: String
    ) {
        self.label = label
        self.domain = domain
        self.plistPath = plistPath
        self.program = program
        self.arguments = arguments
        self.pid = pid
        self.runs = runs
        self.lastExitCode = lastExitCode
        self.immediateReason = immediateReason
        self.keepAlive = keepAlive
        self.runAtLoad = runAtLoad
        self.throttleInterval = throttleInterval
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
        self.recentStderr = recentStderr
        self.severity = severity
        self.explanation = explanation
    }
}

public enum LaunchdRestartStormDetector {
    public static func snapshot(
        domain: String = "user",
        minRuns: Int = 25,
        limit: Int = 20
    ) -> LaunchdRestartStormsResponse {
        let effectiveLimit = max(1, min(limit, 100))
        let effectiveMinRuns = max(1, minRuns)
        var findings: [LaunchdRestartStormFinding] = []
        for scope in scopes(for: domain) {
            findings.append(contentsOf: scan(scope: scope, minRuns: effectiveMinRuns))
        }
        findings.sort { lhs, rhs in
            lhs.runs == rhs.runs ? lhs.label < rhs.label : lhs.runs > rhs.runs
        }
        return LaunchdRestartStormsResponse(findings: Array(findings.prefix(effectiveLimit)))
    }

    static func parseServicePrint(
        _ text: String,
        label: String,
        domain: String,
        plistPath: String,
        plist: [String: Any],
        recentStderr: String?
    ) -> LaunchdRestartStormFinding? {
        let runs = parseInt(after: "runs =", in: text) ?? 0
        let pid = parseInt32(after: "pid =", in: text)
        let lastExit = parseLineValue(after: "last exit code =", in: text)
        let reason = parseLineValue(after: "immediate reason =", in: text)
        let keepAlive = plist["KeepAlive"] as? Bool ?? false
        let runAtLoad = plist["RunAtLoad"] as? Bool ?? false
        let throttle = plist["ThrottleInterval"] as? Int
        let args = plist["ProgramArguments"] as? [String] ?? []
        let program = (plist["Program"] as? String) ?? args.first
        let stdout = plist["StandardOutPath"] as? String
        let stderr = plist["StandardErrorPath"] as? String

        let lowThrottle = (throttle ?? 10) <= 2
        let nonZeroExit = lastExit.map { !$0.contains("never exited") && !$0.hasPrefix("0") } ?? false
        let inefficient = reason?.localizedCaseInsensitiveContains("inefficient") == true
        let suspicious = runs >= 25 && keepAlive && (lowThrottle || inefficient || nonZeroExit)
        guard suspicious else { return nil }

        let severity: String
        if runs >= 1_000 || inefficient { severity = "high" }
        else if runs >= 100 { severity = "medium" }
        else { severity = "low" }

        let throttleText = throttle.map(String.init) ?? "default"
        let explanation = [
            "launchd has started this job \(runs) times",
            keepAlive ? "KeepAlive is enabled" : nil,
            runAtLoad ? "RunAtLoad is enabled" : nil,
            "ThrottleInterval is \(throttleText)",
            lastExit.map { "last exit code: \($0)" },
            reason.map { "immediate reason: \($0)" },
        ].compactMap { $0 }.joined(separator: "; ")

        return LaunchdRestartStormFinding(
            label: label,
            domain: domain,
            plistPath: plistPath,
            program: program,
            arguments: args,
            pid: pid,
            runs: runs,
            lastExitCode: lastExit,
            immediateReason: reason,
            keepAlive: keepAlive,
            runAtLoad: runAtLoad,
            throttleInterval: throttle,
            stdoutPath: stdout,
            stderrPath: stderr,
            recentStderr: recentStderr,
            severity: severity,
            explanation: explanation
        )
    }

    private struct Scope {
        let domain: String
        let directories: [String]
    }

    private static func scopes(for domain: String) -> [Scope] {
        switch domain {
        case "system":
            return [Scope(domain: "system", directories: ["/Library/LaunchDaemons"])]
        case "both":
            return scopes(for: "user") + scopes(for: "system")
        default:
            return [Scope(
                domain: "gui/\(getuid())",
                directories: [NSHomeDirectory() + "/Library/LaunchAgents"]
            )]
        }
    }

    private static func scan(scope: Scope, minRuns: Int) -> [LaunchdRestartStormFinding] {
        plistPaths(in: scope.directories).compactMap { path in
            guard let plist = loadPlist(path),
                  let label = plist["Label"] as? String,
                  let printout = launchctlPrint("\(scope.domain)/\(label)") else {
                return nil
            }
            let recentStderr = (plist["StandardErrorPath"] as? String).flatMap { tail(path: $0, maxBytes: 4_096) }
            guard let finding = parseServicePrint(
                printout,
                label: label,
                domain: scope.domain,
                plistPath: path,
                plist: plist,
                recentStderr: recentStderr
            ) else {
                return nil
            }
            return finding.runs >= minRuns ? finding : nil
        }
    }

    private static func plistPaths(in directories: [String]) -> [String] {
        let fm = FileManager.default
        return directories.flatMap { dir -> [String] in
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
            return files
                .filter { $0.hasSuffix(".plist") }
                .map { (dir as NSString).appendingPathComponent($0) }
        }
    }

    private static func loadPlist(_ path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            return nil
        }
        return dict
    }

    private static func launchctlPrint(_ target: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["print", target]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func tail(path: String, maxBytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > maxBytes ? size - maxBytes : 0)
        let data = handle.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .suffix(8)
            .joined(separator: "\n")
    }

    private static func parseInt(after marker: String, in text: String) -> Int? {
        parseLineValue(after: marker, in: text).flatMap { Int($0) }
    }

    private static func parseInt32(after marker: String, in text: String) -> Int32? {
        parseLineValue(after: marker, in: text).flatMap { Int32($0) }
    }

    private static func parseLineValue(after marker: String, in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(marker) else { continue }
            return String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
