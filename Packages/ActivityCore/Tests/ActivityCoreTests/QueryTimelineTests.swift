import Testing
import Foundation
@testable import ActivityCore
import ActivityCoreTestSupport

@Suite("QueryTimeline")
struct QueryTimelineTests {

    @Test("Empty range yields empty array (not throw)")
    func emptyRange() async throws {
        let store = FakeStore()
        let qt = QueryTimeline(store: store)
        let range = DateInterval(start: Fixtures.epoch, duration: 3600)
        let events = try await qt.events(TimelineQuery(range: range))
        #expect(events.isEmpty)
    }

    @Test("Limit caps results")
    func limit() async throws {
        let store = FakeStore()
        for i in 0..<10 {
            try await store.append([Fixtures.frontmost(bundleID: "com.a", name: "A", at: Double(i))])
        }
        let qt = QueryTimeline(store: store)
        let range = DateInterval(start: Fixtures.epoch, duration: 100)
        let events = try await qt.events(TimelineQuery(range: range, limit: 3))
        #expect(events.count == 3)
    }

    @Test("Bundle filter narrows to matching apps")
    func bundleFilter() async throws {
        let store = FakeStore()
        try await store.append([
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 1),
            Fixtures.frontmost(bundleID: "com.b", name: "B", at: 2),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 3),
        ])
        let qt = QueryTimeline(store: store)
        let range = DateInterval(start: Fixtures.epoch, duration: 100)
        let result = try await qt.events(TimelineQuery(range: range, bundleIDs: ["com.a"]))
        #expect(result.count == 2)
    }

    @Test("Sessions respects gap threshold")
    func sessions() async throws {
        let store = FakeStore()
        try await store.append([
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 30),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 200),
        ])
        let qt = QueryTimeline(store: store)
        let range = DateInterval(start: Fixtures.epoch, duration: 500)
        let sessions = try await qt.sessions(in: range, gapThreshold: 60)
        #expect(sessions.count == 2)
    }

    @Test("Results are deterministically ordered by timestamp then id")
    func deterministicOrdering() async throws {
        let store = FakeStore()
        let t = Fixtures.epoch
        let a = ActivityEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, timestamp: t, source: .frontmost, subject: .app(bundleID: "com.a", name: "A"))
        let b = ActivityEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, timestamp: t, source: .frontmost, subject: .app(bundleID: "com.b", name: "B"))
        try await store.append([b, a])
        let qt = QueryTimeline(store: store)
        let range = DateInterval(start: t.addingTimeInterval(-1), duration: 2)
        let result = try await qt.events(TimelineQuery(range: range))
        #expect(result.first?.id == a.id)
    }
}
