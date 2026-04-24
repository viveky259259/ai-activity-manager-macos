import Foundation

public protocol ActivityStore: Sendable {
    func append(_ events: [ActivityEvent]) async throws
    func events(in range: DateInterval, limit: Int?) async throws -> [ActivityEvent]
    func search(_ query: TimelineQuery) async throws -> [ActivityEvent]
    func sessions(in range: DateInterval, gapThreshold: TimeInterval) async throws -> [ActivitySession]
    func rules() async throws -> [Rule]
    func upsertRule(_ rule: Rule) async throws
    func deleteRule(id: UUID) async throws
}
