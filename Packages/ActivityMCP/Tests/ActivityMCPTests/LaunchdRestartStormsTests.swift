import Foundation
import Testing
@testable import ActivityMCP

@Suite("launchd restart storm detection")
struct LaunchdRestartStormsTests {
    @Test("detects keepalive launch agent restart loops")
    func detectsRestartLoop() throws {
        let printout = """
        gui/501/ai.openclaw.gateway = {
            active count = 1
            path = /Users/vivek/Library/LaunchAgents/ai.openclaw.gateway.plist
            type = LaunchAgent
            state = running

            program = /opt/homebrew/opt/node/bin/node
            runs = 9962
            pid = 63810
            immediate reason = inefficient
            last exit code = 78: EX_CONFIG
        }
        """
        let plist: [String: Any] = [
            "Label": "ai.openclaw.gateway",
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 1,
            "ProgramArguments": [
                "/opt/homebrew/opt/node/bin/node",
                "/opt/homebrew/lib/node_modules/openclaw/dist/index.js",
                "gateway",
            ],
            "StandardErrorPath": "/Users/vivek/.openclaw/logs/gateway.err.log",
        ]

        let finding = try #require(LaunchdRestartStormDetector.parseServicePrint(
            printout,
            label: "ai.openclaw.gateway",
            domain: "gui/501",
            plistPath: "/Users/vivek/Library/LaunchAgents/ai.openclaw.gateway.plist",
            plist: plist,
            recentStderr: "Missing config. Run `openclaw setup`."
        ))

        #expect(finding.label == "ai.openclaw.gateway")
        #expect(finding.runs == 9962)
        #expect(finding.pid == 63810)
        #expect(finding.severity == "high")
        #expect(finding.throttleInterval == 1)
        #expect(finding.lastExitCode == "78: EX_CONFIG")
        #expect(finding.immediateReason == "inefficient")
        #expect(finding.recentStderr?.contains("Missing config") == true)
    }

    @Test("ignores healthy low-run jobs")
    func ignoresHealthyJob() {
        let printout = """
        gui/501/com.example.ok = {
            runs = 1
            pid = 123
            last exit code = (never exited)
        }
        """
        let plist: [String: Any] = [
            "Label": "com.example.ok",
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 10,
        ]

        let finding = LaunchdRestartStormDetector.parseServicePrint(
            printout,
            label: "com.example.ok",
            domain: "gui/501",
            plistPath: "/Users/vivek/Library/LaunchAgents/com.example.ok.plist",
            plist: plist,
            recentStderr: nil
        )

        #expect(finding == nil)
    }
}
