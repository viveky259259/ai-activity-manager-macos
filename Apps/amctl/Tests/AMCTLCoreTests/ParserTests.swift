import Testing
import Foundation
import ArgumentParser
@testable import AMCTLCore

@Suite("AMCTL parser")
struct ParserTests {

    @Test("status parses with default format")
    func statusDefault() throws {
        let cmd = try AMCTL.parseAsRoot(["status"])
        let status = try #require(cmd as? AMCTL.Status)
        #expect(status.format == .human)
        #expect(status.timing == false)
    }

    @Test("status --format json")
    func statusJSON() throws {
        let cmd = try AMCTL.parseAsRoot(["status", "--format", "json"])
        let status = try #require(cmd as? AMCTL.Status)
        #expect(status.format == .json)
    }

    @Test("query captures question and since window")
    func queryCommand() throws {
        let cmd = try AMCTL.parseAsRoot(["query", "how much Xcode today?", "--since", "7d"])
        let q = try #require(cmd as? AMCTL.Query)
        #expect(q.question == "how much Xcode today?")
        #expect(q.since == "7d")
    }

    @Test("timeline parses from/to and --app repeat")
    func timelineCommand() throws {
        let cmd = try AMCTL.parseAsRoot([
            "timeline",
            "--from", "2025-04-01T00:00:00Z",
            "--to", "2025-04-02T00:00:00Z",
            "--app", "com.apple.dt.Xcode",
            "--app", "com.apple.Safari",
            "--format", "ndjson",
        ])
        let t = try #require(cmd as? AMCTL.Timeline)
        #expect(t.from == "2025-04-01T00:00:00Z")
        #expect(t.to == "2025-04-02T00:00:00Z")
        #expect(t.app == ["com.apple.dt.Xcode", "com.apple.Safari"])
        #expect(t.format == .ndjson)
    }

    @Test("events parses source/limit/since")
    func eventsCommand() throws {
        let cmd = try AMCTL.parseAsRoot([
            "events", "--source", "frontmost", "--limit", "50", "--since", "24h",
        ])
        let e = try #require(cmd as? AMCTL.Events)
        #expect(e.source == "frontmost")
        #expect(e.limit == 50)
        #expect(e.since == "24h")
    }

    @Test("top parses --by and --since")
    func topCommand() throws {
        let cmd = try AMCTL.parseAsRoot(["top", "--by", "host", "--since", "30d"])
        let t = try #require(cmd as? AMCTL.Top)
        #expect(t.by == .host)
        #expect(t.since == "30d")
    }

    @Test("rules list default subcommand")
    func rulesListDefault() throws {
        let cmd = try AMCTL.parseAsRoot(["rules"])
        #expect(cmd is AMCTL.Rules.List)
    }

    @Test("rules add picks up NL description")
    func rulesAdd() throws {
        let cmd = try AMCTL.parseAsRoot(["rules", "add", "after 30m of Slack, suggest focus"])
        let add = try #require(cmd as? AMCTL.Rules.Add)
        #expect(add.nl == "after 30m of Slack, suggest focus")
    }

    @Test("actions kill parses bundle + strategy + flags")
    func actionsKill() throws {
        let cmd = try AMCTL.parseAsRoot([
            "actions", "kill", "--bundle", "com.apple.Safari",
            "--strategy", "forceQuit", "--force", "--yes",
        ])
        let kill = try #require(cmd as? AMCTL.Actions.Kill)
        #expect(kill.bundle == "com.apple.Safari")
        #expect(kill.strategy == "forceQuit")
        #expect(kill.force == true)
        #expect(kill.yes == true)
    }

    @Test("actions focus set parses mode name")
    func actionsFocusSet() throws {
        let cmd = try AMCTL.parseAsRoot(["actions", "focus", "set", "Do Not Disturb"])
        let set = try #require(cmd as? AMCTL.Actions.Focus.Set)
        #expect(set.mode == "Do Not Disturb")
    }

    @Test("mcp install --print claude-desktop")
    func mcpInstall() throws {
        let cmd = try AMCTL.parseAsRoot(["mcp", "install", "claude-desktop", "--print"])
        let install = try #require(cmd as? AMCTL.MCP.Install)
        #expect(install.target == .claudeDesktop)
        #expect(install.print == true)
    }

    @Test("permissions check parses name")
    func permissionsCheck() throws {
        let cmd = try AMCTL.parseAsRoot(["permissions", "check", "accessibility"])
        let check = try #require(cmd as? AMCTL.Permissions.Check)
        #expect(check.name == "accessibility")
    }

    @Test("invalid --format value is rejected")
    func invalidFormatRejected() {
        #expect(throws: (any Error).self) {
            _ = try AMCTL.parseAsRoot(["status", "--format", "yaml"])
        }
    }

    @Test("timeline rejects bogus ISO timestamps in validate()")
    func timelineInvalidDates() {
        #expect(throws: (any Error).self) {
            _ = try AMCTL.parseAsRoot([
                "timeline", "--from", "not-a-date", "--to", "2025-04-02T00:00:00Z",
            ])
        }
    }
}
