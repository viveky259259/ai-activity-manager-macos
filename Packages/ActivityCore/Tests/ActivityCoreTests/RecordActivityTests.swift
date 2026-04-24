import Testing
import Foundation
@testable import ActivityCore
import ActivityCoreTestSupport

@Suite("RecordActivity")
struct RecordActivityTests {

    @Test("Single event flushes to store")
    func singleEvent() async throws {
        let store = FakeStore()
        let rec = RecordActivity(store: store, flushWindow: 0.02)
        await rec.ingest(Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0))
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.storedEvents.count == 1)
    }

    @Test("Multiple events inside window coalesce into one append")
    func batchCoalesces() async throws {
        let store = FakeStore()
        let rec = RecordActivity(store: store, flushWindow: 0.05)
        for i in 0..<10 {
            await rec.ingest(Fixtures.frontmost(bundleID: "com.a", name: "A", at: Double(i)))
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(store.storedEvents.count == 10)
        #expect(store.appendCalls == 1)
    }

    @Test("flushNow drains pending immediately")
    func flushNowDrains() async throws {
        let store = FakeStore()
        let rec = RecordActivity(store: store, flushWindow: 10)
        await rec.ingest(Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0))
        await rec.flushNow()
        #expect(store.storedEvents.count == 1)
    }
}
