import Foundation
import Testing
import ActivityCore
@testable import ActivityIPC

@Suite("IPC DTO round-trips")
struct DTOTests {
    private func roundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try IPCCoder.encoder().encode(value)
        let decoded = try IPCCoder.decoder().decode(T.self, from: data)
        #expect(decoded == value)
    }

    @Test func statusResponse() throws {
        try roundTrip(StatusResponse(
            sources: ["frontmost"],
            capturedEventCount: 100,
            actionsEnabled: true,
            permissions: ["calendar": "granted", "screenRecording": "denied"]
        ))
    }

    @Test func queryRequestResponse() throws {
        let range = DateInterval(start: Date(timeIntervalSince1970: 10), duration: 3600)
        try roundTrip(QueryRequest(question: "what did I do?", range: range))

        let session = ActivitySession(
            subject: .app(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            sampleCount: 4
        )
        try roundTrip(QueryResponse(
            answer: "you coded",
            cited: [session],
            provider: "local-llama",
            tookMillis: 123
        ))
    }

    @Test func timelineRequestResponse() throws {
        try roundTrip(TimelineRequest(
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 60),
            bundleIDs: ["com.apple.Safari"],
            limit: 50
        ))
        try roundTrip(TimelineResponse(sessions: []))
    }

    @Test func eventsRequestResponse() throws {
        try roundTrip(EventsRequest(
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 60),
            source: .frontmost,
            limit: 200
        ))

        let event = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 5),
            source: .frontmost,
            subject: .app(bundleID: "com.apple.Safari", name: "Safari"),
            attributes: ["url": "https://apple.com"]
        )
        try roundTrip(EventsResponse(events: [event]))
    }

    @Test func rulesDTOs() throws {
        let rule = Rule(
            name: "quiet during focus",
            nlSource: "be quiet when focused",
            trigger: .focusModeChanged(to: "Work"),
            actions: [.logMessage("quiet")],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        try roundTrip(RulesResponse(rules: [rule]))
        try roundTrip(AddRuleRequest(nl: "kill Slack after 10 minutes"))
        try roundTrip(AddRuleResponse(rule: rule))
        try roundTrip(ToggleRuleRequest(id: rule.id, enabled: false))
        try roundTrip(DeleteRuleRequest(id: rule.id))
    }

    @Test func actionDTOs() throws {
        try roundTrip(KillAppRequest(
            bundleID: "com.tinyspeck.slackmacgap",
            strategy: .politeQuit,
            force: false,
            confirmed: true
        ))
        try roundTrip(KillAppResponse(outcome: "succeeded"))
        try roundTrip(SetFocusRequest(mode: "Work"))
        try roundTrip(SetFocusRequest(mode: nil))
    }

    @Test func tailRequest() throws {
        try roundTrip(TailRequest(sources: [.frontmost, .idle]))
        try roundTrip(TailRequest(sources: nil))
    }

    @Test func emptyResponse() throws {
        try roundTrip(EmptyResponse())
    }
}
