import Testing
import Foundation
@testable import ActivityStore
import ActivityCore
import ActivityCoreTestSupport

@Suite("SQLiteActivityStore")
struct SQLiteActivityStoreTests {

    func newStore() throws -> SQLiteActivityStore {
        try SQLiteActivityStore.temporary()
    }

    @Test("Empty range returns empty array")
    func emptyRange() async throws {
        let store = try newStore()
        let range = DateInterval(start: Fixtures.epoch, duration: 3600)
        let events = try await store.events(in: range, limit: nil)
        #expect(events.isEmpty)
    }

    @Test("Append and query round-trips single event")
    func singleEventRoundTrip() async throws {
        let store = try newStore()
        let event = Fixtures.frontmost(bundleID: "com.apple.Xcode", name: "Xcode", at: 0)
        try await store.append([event])
        let range = DateInterval(start: Fixtures.epoch.addingTimeInterval(-1), duration: 10)
        let got = try await store.events(in: range, limit: nil)
        #expect(got.count == 1)
        #expect(got[0] == event)
    }

    @Test("Batch append preserves order + values")
    func batchAppend() async throws {
        let store = try newStore()
        let events = (0..<20).map { i in
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: Double(i))
        }
        try await store.append(events)
        let range = DateInterval(start: Fixtures.epoch, duration: 1000)
        let got = try await store.events(in: range, limit: nil)
        #expect(got.count == 20)
        for i in 0..<20 {
            #expect(got[i].timestamp == events[i].timestamp)
        }
    }

    @Test("Limit caps results")
    func limit() async throws {
        let store = try newStore()
        let events = (0..<50).map { i in
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: Double(i))
        }
        try await store.append(events)
        let range = DateInterval(start: Fixtures.epoch, duration: 1000)
        let got = try await store.events(in: range, limit: 10)
        #expect(got.count == 10)
    }

    @Test("Search by bundle ID filters correctly")
    func searchByBundle() async throws {
        let store = try newStore()
        try await store.append([
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0),
            Fixtures.frontmost(bundleID: "com.b", name: "B", at: 1),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 2),
        ])
        let range = DateInterval(start: Fixtures.epoch, duration: 100)
        let query = TimelineQuery(range: range, bundleIDs: ["com.a"])
        let got = try await store.search(query)
        #expect(got.count == 2)
    }

    @Test("Search by source filters correctly")
    func searchBySource() async throws {
        let store = try newStore()
        try await store.append([
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0),
            Fixtures.idle(transition: "entered", at: 10),
        ])
        let range = DateInterval(start: Fixtures.epoch, duration: 100)
        let got = try await store.search(TimelineQuery(range: range, sources: [.idle]))
        #expect(got.count == 1)
        #expect(got[0].source == .idle)
    }

    @Test("Search FTS matches window subject text")
    func searchFTS() async throws {
        let store = try newStore()
        try await store.append([
            Fixtures.frontmost(bundleID: "com.apple.Xcode", name: "Xcode", at: 0),
            Fixtures.frontmost(bundleID: "com.figma.Desktop", name: "Figma", at: 1),
        ])
        let range = DateInterval(start: Fixtures.epoch, duration: 100)
        let got = try await store.search(TimelineQuery(range: range, fullText: "Figma"))
        #expect(got.count == 1)
        if case .app(_, let name) = got[0].subject {
            #expect(name == "Figma")
        } else {
            Issue.record("expected app subject")
        }
    }

    @Test("Rules upsert + fetch")
    func rulesUpsertFetch() async throws {
        let store = try newStore()
        let rule = Fixtures.rule(
            name: "test",
            trigger: .appFocused(bundleID: "com.a", durationAtLeast: 60),
            actions: [.logMessage("hi")]
        )
        try await store.upsertRule(rule)
        let fetched = try await store.rules()
        #expect(fetched.count == 1)
        #expect(fetched[0].id == rule.id)
        #expect(fetched[0].name == "test")
    }

    @Test("Rules update overwrites fields")
    func rulesUpdate() async throws {
        let store = try newStore()
        var rule = Fixtures.rule(
            name: "v1",
            trigger: .appFocused(bundleID: "com.a", durationAtLeast: nil),
            actions: [.logMessage("x")]
        )
        try await store.upsertRule(rule)
        rule.name = "v2"
        try await store.upsertRule(rule)
        let got = try await store.rules()
        #expect(got.count == 1)
        #expect(got[0].name == "v2")
    }

    @Test("Rules delete removes rule")
    func rulesDelete() async throws {
        let store = try newStore()
        let rule = Fixtures.rule(
            name: "x",
            trigger: .idleEnded,
            actions: [.logMessage("x")]
        )
        try await store.upsertRule(rule)
        try await store.deleteRule(id: rule.id)
        let got = try await store.rules()
        #expect(got.isEmpty)
    }

    @Test("Sessions collapse persisted events")
    func sessionsFromStore() async throws {
        let store = try newStore()
        try await store.append([
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 30),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 200),
        ])
        let range = DateInterval(start: Fixtures.epoch, duration: 500)
        let sessions = try await store.sessions(in: range, gapThreshold: 60)
        #expect(sessions.count == 2)
    }

    @Test("Deterministic order: timestamp asc, id asc")
    func deterministicOrder() async throws {
        let store = try newStore()
        let a = ActivityEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: Fixtures.epoch,
            source: .frontmost,
            subject: .app(bundleID: "com.a", name: "A")
        )
        let b = ActivityEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            timestamp: Fixtures.epoch,
            source: .frontmost,
            subject: .app(bundleID: "com.b", name: "B")
        )
        try await store.append([b, a])
        let range = DateInterval(start: Fixtures.epoch.addingTimeInterval(-1), duration: 2)
        let got = try await store.events(in: range, limit: nil)
        #expect(got.first?.id == a.id)
    }

    @Test("Migrating twice is idempotent")
    func migrationIdempotent() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("migrate-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let s1 = try SQLiteActivityStore(url: url)
        try await s1.append([Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0)])
        let s2 = try SQLiteActivityStore(url: url)
        let range = DateInterval(start: Fixtures.epoch.addingTimeInterval(-1), duration: 100)
        let got = try await s2.events(in: range, limit: nil)
        #expect(got.count == 1)
    }
}
