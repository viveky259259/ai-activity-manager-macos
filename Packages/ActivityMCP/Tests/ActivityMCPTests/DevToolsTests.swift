import Foundation
import Testing
import ActivityCore
import ActivityIPC
@testable import ActivityMCP

@Suite("Dev-shaped read tools")
struct DevToolsTests {
    /// Build an event with bundleID, app name, timestamp, and an optional window title.
    private func event(
        bundleID: String,
        appName: String,
        title: String?,
        at timestamp: Date
    ) -> ActivityEvent {
        ActivityEvent(
            timestamp: timestamp,
            source: .frontmost,
            subject: .app(bundleID: bundleID, name: appName),
            attributes: title.map { ["windowTitle": $0] } ?? [:]
        )
    }

    private func tool(_ name: String, _ tools: [ToolDefinition]) throws -> ToolDefinition {
        try #require(tools.first(where: { $0.name == name }))
    }

    @Test("recent_projects groups window titles by repo and reports hours")
    func recentProjectsAggregates() async throws {
        let client = FakeActivityClient()
        let base = Date(timeIntervalSinceNow: -3600)
        client.setEvents(EventsResponse(events: [
            event(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor",
                  title: "auth.swift — auth-service",
                  at: base),
            event(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor",
                  title: "routes.swift — auth-service",
                  at: base.addingTimeInterval(120)),
            event(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                  title: "widgetshop — Models.swift",
                  at: base.addingTimeInterval(240)),
        ]))

        let tools = ReadTools.make(client: client)
        let recent = try tool("recent_projects", tools)
        let result = try await recent.handler(.object(["window": .string("24h")]))

        guard case .object(let obj) = result,
              case .array(let projects) = obj["projects"] else {
            Issue.record("expected projects array, got \(result)")
            return
        }
        #expect(projects.count == 2)

        let repos = projects.compactMap { (proj: JSONValue) -> String? in
            guard case .object(let o) = proj, case .string(let r) = o["repo"] else { return nil }
            return r
        }
        #expect(Set(repos) == ["auth-service", "widgetshop"])
    }

    @Test("recent_projects ignores non-IDE events")
    func recentProjectsIgnoresNonIDE() async throws {
        let client = FakeActivityClient()
        let now = Date()
        client.setEvents(EventsResponse(events: [
            event(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack",
                  title: "Slack — #engineering",
                  at: now.addingTimeInterval(-300)),
        ]))

        let tools = ReadTools.make(client: client)
        let recent = try tool("recent_projects", tools)
        let result = try await recent.handler(.object([:]))

        guard case .object(let obj) = result, case .array(let projects) = obj["projects"] else {
            Issue.record("expected projects array")
            return
        }
        #expect(projects.isEmpty)
    }

    @Test("time_per_repo ranks repos by total seconds")
    func timePerRepoRanks() async throws {
        let client = FakeActivityClient()
        let base = Date(timeIntervalSinceNow: -7200)
        // alpha gets 2 samples = ~ up to 5min credit each
        // beta gets 1 sample = closed by next event
        client.setEvents(EventsResponse(events: [
            event(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor",
                  title: "a.swift — alpha", at: base),
            event(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor",
                  title: "b.swift — alpha", at: base.addingTimeInterval(60)),
            event(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor",
                  title: "c.swift — beta", at: base.addingTimeInterval(300)),
        ]))

        let tools = ReadTools.make(client: client)
        let perRepo = try tool("time_per_repo", tools)
        let result = try await perRepo.handler(.object([:]))

        guard case .object(let obj) = result, case .array(let repos) = obj["repos"] else {
            Issue.record("expected repos array")
            return
        }
        #expect(repos.count == 2)
        guard case .object(let first) = repos.first,
              case .string(let firstName) = first["repo"] else {
            Issue.record("expected first repo to be an object with name")
            return
        }
        #expect(firstName == "alpha")
    }

    @Test("files_touched returns distinct files for a repo, latest first")
    func filesTouchedReturnsFiles() async throws {
        let client = FakeActivityClient()
        let base = Date(timeIntervalSinceNow: -1800)
        client.setEvents(EventsResponse(events: [
            event(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor",
                  title: "auth.swift — auth-service", at: base),
            event(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor",
                  title: "routes.swift — auth-service", at: base.addingTimeInterval(60)),
            event(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor",
                  title: "auth.swift — auth-service", at: base.addingTimeInterval(120)),
            event(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                  title: "Other.swift — other-repo", at: base.addingTimeInterval(180)),
        ]))

        let tools = ReadTools.make(client: client)
        let touched = try tool("files_touched", tools)
        let result = try await touched.handler(.object([
            "repo": .string("auth-service"),
        ]))

        guard case .object(let obj) = result, case .array(let files) = obj["files"] else {
            Issue.record("expected files array")
            return
        }
        let paths = files.compactMap { (entry: JSONValue) -> String? in
            guard case .object(let o) = entry, case .string(let p) = o["path"] else { return nil }
            return p
        }
        #expect(Set(paths) == ["auth.swift", "routes.swift"])
        #expect(paths.first == "auth.swift")  // most recent last_seen wins ordering
    }

    @Test("files_touched returns empty list for unknown repo")
    func filesTouchedUnknownRepo() async throws {
        let client = FakeActivityClient()
        client.setEvents(EventsResponse(events: []))

        let tools = ReadTools.make(client: client)
        let touched = try tool("files_touched", tools)
        let result = try await touched.handler(.object([
            "repo": .string("does-not-exist"),
        ]))

        guard case .object(let obj) = result, case .array(let files) = obj["files"] else {
            Issue.record("expected files array")
            return
        }
        #expect(files.isEmpty)
    }

    @Test("files_touched rejects missing repo arg")
    func filesTouchedRequiresRepo() async throws {
        let client = FakeActivityClient()
        let tools = ReadTools.make(client: client)
        let touched = try tool("files_touched", tools)
        await #expect(throws: JSONRPCError.self) {
            _ = try await touched.handler(.object([:]))
        }
    }

    @Test("current_context picks the latest IDE event with a window title")
    func currentContextLatest() async throws {
        let client = FakeActivityClient()
        let now = Date()
        client.setEvents(EventsResponse(events: [
            event(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor",
                  title: "auth.swift — auth-service",
                  at: now.addingTimeInterval(-180)),
            event(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                  title: "ai_activity_manager — ReadTools.swift",
                  at: now.addingTimeInterval(-30)),
        ]))

        let tools = ReadTools.make(client: client)
        let context = try tool("current_context", tools)
        let result = try await context.handler(.object([:]))

        guard case .object(let obj) = result else {
            Issue.record("expected object result")
            return
        }
        #expect(obj["app"] == .string("Xcode"))
        #expect(obj["repo"] == .string("ai_activity_manager"))
        #expect(obj["file"] == .string("ReadTools.swift"))
    }

    @Test("current_context returns null fields when no IDE events present")
    func currentContextEmpty() async throws {
        let client = FakeActivityClient()
        client.setEvents(EventsResponse(events: []))

        let tools = ReadTools.make(client: client)
        let context = try tool("current_context", tools)
        let result = try await context.handler(.object([:]))

        guard case .object(let obj) = result else {
            Issue.record("expected object result")
            return
        }
        #expect(obj["repo"] == .null)
        #expect(obj["file"] == .null)
    }

    @Test("parseWindow parses common shorthand")
    func parseWindowShorthand() {
        #expect(ReadTools.parseWindow(.string("24h")) == 86_400)
        #expect(ReadTools.parseWindow(.string("7d")) == 604_800)
        #expect(ReadTools.parseWindow(.string("90m")) == 5_400)
        #expect(ReadTools.parseWindow(.string("30s")) == 30)
        #expect(ReadTools.parseWindow(.string("not-a-window")) == nil)
        #expect(ReadTools.parseWindow(nil) == nil)
    }
}
