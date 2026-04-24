import Foundation
import ActivityCore

/// View-model for the timeline window. Loads sessions from the injected
/// `ActivityStore` port so tests can substitute a fake.
@MainActor
@Observable
public final class TimelineViewModel {
    public var sessions: [ActivitySession] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    private let store: any ActivityStore
    private let gapThreshold: TimeInterval

    public init(store: any ActivityStore, gapThreshold: TimeInterval = 120) {
        self.store = store
        self.gapThreshold = gapThreshold
    }

    public func load(from: Date, to: Date) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let range = DateInterval(start: min(from, to), end: max(from, to))
        do {
            let loaded = try await store.sessions(in: range, gapThreshold: gapThreshold)
            self.sessions = loaded
        } catch {
            self.errorMessage = String(describing: error)
            self.sessions = []
        }
    }
}
