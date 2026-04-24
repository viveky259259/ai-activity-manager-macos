import Foundation

public struct QueryTimeline: Sendable {
    private let store: ActivityStore
    private let collapser: SessionCollapser

    public init(store: ActivityStore, collapser: SessionCollapser = SessionCollapser()) {
        self.store = store
        self.collapser = collapser
    }

    public func events(_ query: TimelineQuery) async throws -> [ActivityEvent] {
        try await store.search(query)
    }

    public func sessions(in range: DateInterval, gapThreshold: TimeInterval = 60) async throws -> [ActivitySession] {
        let events = try await store.events(in: range, limit: nil)
        return collapser.collapse(events, gapThreshold: gapThreshold)
    }
}
