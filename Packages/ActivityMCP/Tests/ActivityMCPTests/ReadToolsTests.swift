import Foundation
import Testing
import ActivityCore
import ActivityIPC
@testable import ActivityMCP

@Suite("ReadTools")
struct ReadToolsTests {
    @Test("timeline_range maps arguments to TimelineRequest and serializes sessions")
    func timelineRangeMapsArgs() async throws {
        let client = FakeActivityClient()
        let session = ActivitySession(
            subject: .app(bundleID: "com.apple.Safari", name: "Safari"),
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            endedAt: Date(timeIntervalSince1970: 1_000_600),
            sampleCount: 3
        )
        client.setTimeline(TimelineResponse(sessions: [session]))

        let tools = ReadTools.make(client: client)
        let tool = try #require(tools.first(where: { $0.name == "timeline_range" }))

        let args: JSONValue = .object([
            "from": .string("2023-11-14T22:13:20Z"),
            "to": .string("2023-11-14T22:23:20Z"),
            "app_filter": .array([.string("com.apple.Safari")]),
            "limit": .int(50),
        ])
        let result = try await tool.handler(args)

        // Ensure request went through with bundleIDs and limit forwarded
        let captured = try #require(client.capturedTimelineRequest)
        #expect(captured.bundleIDs == ["com.apple.Safari"])
        #expect(captured.limit == 50)

        guard case .object(let obj) = result, case .array(let sessions) = obj["sessions"] else {
            Issue.record("expected sessions array, got \(result)")
            return
        }
        #expect(sessions.count == 1)
    }

    @Test("list_rules returns rule data as JSON")
    func listRulesReturnsRules() async throws {
        let client = FakeActivityClient()
        let rule = Rule(
            name: "do thing",
            nlSource: "when X then Y",
            trigger: .idleEnded,
            condition: nil,
            actions: [.logMessage("hi")],
            mode: .active,
            confirm: .never,
            cooldown: 60,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        client.setRules(RulesResponse(rules: [rule]))

        let tools = ReadTools.make(client: client)
        let tool = try #require(tools.first(where: { $0.name == "list_rules" }))
        let result = try await tool.handler(.object([:]))

        guard case .object(let obj) = result, case .array(let rules) = obj["rules"] else {
            Issue.record("expected rules array")
            return
        }
        #expect(rules.count == 1)
    }

    @Test("events_search forwards query and limit and returns events array")
    func eventsSearchForwards() async throws {
        let client = FakeActivityClient()
        let event = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            source: .frontmost,
            subject: .app(bundleID: "com.apple.Safari", name: "Safari")
        )
        client.setEvents(EventsResponse(events: [event]))

        let tools = ReadTools.make(client: client)
        let tool = try #require(tools.first(where: { $0.name == "events_search" }))
        let args: JSONValue = .object([
            "query": .string("safari"),
            "limit": .int(10),
            "from": .string("2023-11-14T22:13:20Z"),
            "to": .string("2023-11-14T22:23:20Z"),
        ])
        let result = try await tool.handler(args)

        let captured = try #require(client.capturedEventsRequest)
        #expect(captured.limit == 10)

        guard case .object(let obj) = result, case .array(let events) = obj["events"] else {
            Issue.record("expected events array")
            return
        }
        #expect(events.count == 1)
    }

    @Test("current_activity returns status fields")
    func currentActivityReturnsStatus() async throws {
        let client = FakeActivityClient()
        client.setStatus(StatusResponse(
            sources: ["frontmost", "idle"],
            capturedEventCount: 42,
            actionsEnabled: true,
            permissions: ["screen": "granted"]
        ))

        let tools = ReadTools.make(client: client)
        let tool = try #require(tools.first(where: { $0.name == "current_activity" }))
        let result = try await tool.handler(.object([:]))

        guard case .object(let obj) = result else {
            Issue.record("expected object")
            return
        }
        #expect(obj["captured_event_count"] == .int(42) || obj["capturedEventCount"] == .int(42))
    }

    @Test("registry exposes every read tool including dev-shaped helpers")
    func allReadToolsListed() async throws {
        let client = FakeActivityClient()
        let tools = ReadTools.make(client: client)
        let names = Set(tools.map { $0.name })
        let expected: Set<String> = [
            "current_activity",
            "timeline_range",
            "timeline_query",
            "events_search",
            "app_usage",
            "list_rules",
            "rule_explain",
            "list_processes",
            "recent_projects",
            "time_per_repo",
            "files_touched",
            "current_context",
        ]
        #expect(names == expected)
    }
}
