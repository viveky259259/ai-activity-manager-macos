import Foundation
import Testing
import ActivityCore
import ActivityIPC
@testable import ActivityMCP

@Suite("system slowdown diagnostics")
struct SystemSlowdownDiagnosticsTests {
    @Test("ranks launchd restart storms above ordinary process pressure")
    func ranksRestartStormsAboveProcesses() throws {
        let process = ProcessSnapshot(
            pid: 42,
            bundleID: "com.example.Worker",
            name: "Worker",
            user: "vivek",
            memoryBytes: 512_000_000,
            cpuPercent: 92,
            threads: 12,
            isFrontmost: false,
            isRestricted: false
        )
        let page = ProcessesPage(
            processes: [process],
            systemMemoryUsedBytes: 8_000_000_000,
            systemMemoryTotalBytes: 16_000_000_000,
            sampledAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let storm = LaunchdRestartStormFinding(
            label: "ai.openclaw.gateway",
            domain: "gui/501",
            plistPath: "/Users/vivek/Library/LaunchAgents/ai.openclaw.gateway.plist",
            program: "/opt/homebrew/bin/node",
            arguments: ["/opt/homebrew/bin/node", "gateway"],
            pid: nil,
            runs: 9_962,
            lastExitCode: "78: EX_CONFIG",
            immediateReason: "inefficient",
            keepAlive: true,
            runAtLoad: true,
            throttleInterval: 1,
            stdoutPath: nil,
            stderrPath: "/Users/vivek/.openclaw/logs/gateway.err.log",
            recentStderr: "Missing config",
            severity: "high",
            explanation: "launchd has started this job 9962 times"
        )

        let response = SystemSlowdownDiagnostics.makeResponse(
            cpuProcesses: page,
            memoryProcesses: page,
            launchdStorms: LaunchdRestartStormsResponse(
                findings: [storm],
                sampledAt: Date(timeIntervalSince1970: 1_700_000_001)
            ),
            minCPUPercent: 20,
            minMemoryBytes: 1_073_741_824,
            limit: 10
        )

        #expect(response.findings.count == 2)
        #expect(response.findings[0].kind == "launchd_restart_storm")
        #expect(response.findings[0].title == "ai.openclaw.gateway")
        #expect(response.findings[1].kind == "process")
        #expect(response.findings[1].process?.pid == 42)
    }

    @Test("diagnose_system_slowdown samples CPU and memory processes")
    func toolSamplesProcesses() async throws {
        let process = ProcessSnapshot(
            pid: 7,
            bundleID: nil,
            name: "indexer",
            user: "vivek",
            memoryBytes: 2_500_000_000,
            cpuPercent: 5,
            threads: 4,
            isFrontmost: false,
            isRestricted: false
        )
        let client = FakeActivityClient()
        client.setListProcesses(ProcessesPage(
            processes: [process],
            systemMemoryUsedBytes: nil,
            systemMemoryTotalBytes: nil,
            sampledAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let tool = try #require(ReadTools.make(client: client).first { $0.name == "diagnose_system_slowdown" })

        let result = try await tool.handler(.object([
            "include_launchd": .bool(false),
            "min_cpu_percent": .double(20),
            "min_memory_bytes": .int(1_000_000_000),
            "process_sample_limit": .int(25),
        ]))

        let captured = try #require(client.capturedListProcessesRequest)
        #expect(captured.limit == 25)
        #expect(captured.includeRestricted == true)

        guard case .object(let obj) = result,
              case .array(let findings) = obj["findings"],
              case .object(let first) = findings.first else {
            Issue.record("expected findings array, got \(result)")
            return
        }

        #expect(first["kind"] == .string("process"))
        #expect(first["title"] == .string("indexer (7)"))
    }
}
