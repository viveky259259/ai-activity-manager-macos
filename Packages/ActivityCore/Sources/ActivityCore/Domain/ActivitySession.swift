import Foundation

public struct ActivitySession: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let subject: ActivityEvent.Subject
    public let startedAt: Date
    public let endedAt: Date
    public let sampleCount: Int

    public init(
        id: UUID = UUID(),
        subject: ActivityEvent.Subject,
        startedAt: Date,
        endedAt: Date,
        sampleCount: Int
    ) {
        self.id = id
        self.subject = subject
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sampleCount = sampleCount
    }

    public var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}
