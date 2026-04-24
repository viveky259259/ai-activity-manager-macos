import Testing
import Foundation
@testable import ActivityCore

@Suite("Domain types")
struct DomainTests {

    @Test("ActivityEvent round-trips through JSON")
    func activityEventCodable() throws {
        let event = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 1000),
            source: .frontmost,
            subject: .app(bundleID: "com.apple.Xcode", name: "Xcode"),
            attributes: ["k": "v"]
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ActivityEvent.self, from: data)
        #expect(decoded == event)
    }

    @Test("All Subject cases are codable")
    func subjectCodable() throws {
        let subjects: [ActivityEvent.Subject] = [
            .app(bundleID: "com.x.y", name: "Y"),
            .url(host: "example.com", path: "/p"),
            .calendarEvent(id: "evt-1", title: "Standup"),
            .focusMode(name: "Deep"),
            .idleSpan(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60)),
            .screenshotText(snippet: "hello"),
            .ruleFired(ruleID: UUID(), ruleName: "r"),
            .custom(kind: "k", identifier: "id")
        ]
        for s in subjects {
            let data = try JSONEncoder().encode(s)
            let back = try JSONDecoder().decode(ActivityEvent.Subject.self, from: data)
            #expect(back == s)
        }
    }

    @Test("Rule round-trips through JSON")
    func ruleCodable() throws {
        let rule = Rule(
            name: "r",
            nlSource: "when in x do y",
            trigger: .appFocused(bundleID: "com.a.b", durationAtLeast: 60),
            condition: .and([.betweenHours(start: 9, end: 17), .weekday([2, 3, 4])]),
            actions: [.setFocusMode(name: "Deep"), .logMessage("hi")],
            mode: .active,
            confirm: .once,
            cooldown: 300,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let data = try JSONEncoder().encode(rule)
        let back = try JSONDecoder().decode(Rule.self, from: data)
        #expect(back == rule)
    }

    @Test("Trigger.Kind covers every Trigger case")
    func triggerKindCoverage() {
        let triggers: [Trigger] = [
            .appFocused(bundleID: "a", durationAtLeast: nil),
            .appFocusLost(bundleID: "a"),
            .urlHostVisited(host: "a", durationAtLeast: nil),
            .idleEntered(after: 60),
            .idleEnded,
            .calendarEventStarted(titleMatches: nil),
            .calendarEventEnded(titleMatches: nil),
            .focusModeChanged(to: nil),
            .timeOfDay(hour: 9, minute: 0, weekdays: [2])
        ]
        let kinds = Set(triggers.map(\.kind))
        #expect(kinds.count == triggers.count)
    }

    @Test("ActivitySession duration computes seconds")
    func sessionDuration() {
        let s = ActivitySession(
            subject: .app(bundleID: "a", name: "A"),
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 250),
            sampleCount: 3
        )
        #expect(s.duration == 150)
    }
}
