import Foundation

public struct TimelineQuery: Hashable, Sendable, Codable {
    public var range: DateInterval
    public var sources: Set<ActivityEvent.Source>?
    public var bundleIDs: Set<String>?
    public var hostContains: String?
    public var fullText: String?
    public var limit: Int?

    public init(
        range: DateInterval,
        sources: Set<ActivityEvent.Source>? = nil,
        bundleIDs: Set<String>? = nil,
        hostContains: String? = nil,
        fullText: String? = nil,
        limit: Int? = nil
    ) {
        self.range = range
        self.sources = sources
        self.bundleIDs = bundleIDs
        self.hostContains = hostContains
        self.fullText = fullText
        self.limit = limit
    }
}

public struct QueryAnswer: Hashable, Sendable, Codable {
    public var answer: String
    public var citedSessions: [ActivitySession]
    public var provider: String
    public var tookMillis: Int

    public init(answer: String, citedSessions: [ActivitySession], provider: String, tookMillis: Int) {
        self.answer = answer
        self.citedSessions = citedSessions
        self.provider = provider
        self.tookMillis = tookMillis
    }
}
