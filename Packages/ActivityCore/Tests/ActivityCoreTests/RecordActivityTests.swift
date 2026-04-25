import Testing
import Foundation
@testable import ActivityCore
import ActivityCoreTestSupport

/// Poll a condition until it becomes true or the timeout elapses. Tests use
/// this to absorb async scheduler jitter on CI without coupling to a fixed
/// sleep duration.
private func waitFor(
    timeout: TimeInterval,
    poll: TimeInterval = 0.01,
    _ condition: () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() >= deadline { return }
        try await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
    }
}

@Suite("RecordActivity")
struct RecordActivityTests {

    @Test("Single event flushes to store")
    func singleEvent() async throws {
        let store = FakeStore()
        let rec = RecordActivity(store: store, flushWindow: 0.02)
        await rec.ingest(Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0))
        // Poll up to 2s to absorb CI scheduler jitter on slow runners. The
        // debounce window is 20ms, so this normally completes in <30ms.
        try await waitFor(timeout: 2.0) { store.storedEvents.count == 1 }
        #expect(store.storedEvents.count == 1)
    }

    @Test("Multiple events inside window coalesce into one append")
    func batchCoalesces() async throws {
        let store = FakeStore()
        let rec = RecordActivity(store: store, flushWindow: 0.05)
        for i in 0..<10 {
            await rec.ingest(Fixtures.frontmost(bundleID: "com.a", name: "A", at: Double(i)))
        }
        try await waitFor(timeout: 2.0) { store.storedEvents.count == 10 }
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
