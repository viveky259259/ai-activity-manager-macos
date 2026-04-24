import Foundation
import Testing
import ActivityCore
import ActivityCoreTestSupport
@testable import ActivityManagerCore

@Suite
@MainActor
struct TimelineViewModelTests {
    @Test
    func loadPopulatesSessionsFromStore() async throws {
        let store = FakeStore()
        let base = Fixtures.epoch
        // Three events for the same bundle within a short window — should
        // collapse into a single session under the default gap threshold.
        try await store.append([
            Fixtures.frontmost(bundleID: "com.apple.Safari", name: "Safari", at: 0, base: base),
            Fixtures.frontmost(bundleID: "com.apple.Safari", name: "Safari", at: 30, base: base),
            Fixtures.frontmost(bundleID: "com.apple.Safari", name: "Safari", at: 60, base: base),
        ])

        let viewModel = TimelineViewModel(store: store)
        let start = base.addingTimeInterval(-60)
        let end = base.addingTimeInterval(3600)
        await viewModel.load(from: start, to: end)

        #expect(!viewModel.isLoading)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.sessions.count >= 1)
        if let first = viewModel.sessions.first {
            if case .app(_, let name) = first.subject {
                #expect(name == "Safari")
            } else {
                Issue.record("Expected an app subject, got \(first.subject)")
            }
        }
    }

    @Test
    func loadWithEmptyStoreProducesNoSessions() async {
        let store = FakeStore()
        let viewModel = TimelineViewModel(store: store)

        let now = Date()
        await viewModel.load(from: now.addingTimeInterval(-3600), to: now)

        #expect(viewModel.sessions.isEmpty)
        #expect(!viewModel.isLoading)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func loadNormalisesSwappedDates() async throws {
        let store = FakeStore()
        let base = Fixtures.epoch
        try await store.append([
            Fixtures.frontmost(bundleID: "com.apple.Notes", name: "Notes", at: 10, base: base),
        ])
        let viewModel = TimelineViewModel(store: store)

        // Pass `from` > `to` — view-model should still produce a valid range.
        let later = base.addingTimeInterval(3600)
        let earlier = base.addingTimeInterval(-60)
        await viewModel.load(from: later, to: earlier)

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.sessions.count == 1)
    }
}
