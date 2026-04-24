import Foundation
import ActivityCore

// MARK: - Status

public struct StatusResponse: Codable, Sendable, Equatable {
    public let sources: [String]
    public let capturedEventCount: Int
    public let actionsEnabled: Bool
    public let permissions: [String: String]

    public init(
        sources: [String],
        capturedEventCount: Int,
        actionsEnabled: Bool,
        permissions: [String: String]
    ) {
        self.sources = sources
        self.capturedEventCount = capturedEventCount
        self.actionsEnabled = actionsEnabled
        self.permissions = permissions
    }
}

// MARK: - Query

public struct QueryRequest: Codable, Sendable, Equatable {
    public let question: String
    public let range: DateInterval

    public init(question: String, range: DateInterval) {
        self.question = question
        self.range = range
    }
}

public struct QueryResponse: Codable, Sendable, Equatable {
    public let answer: String
    public let cited: [ActivitySession]
    public let provider: String
    public let tookMillis: Int

    public init(answer: String, cited: [ActivitySession], provider: String, tookMillis: Int) {
        self.answer = answer
        self.cited = cited
        self.provider = provider
        self.tookMillis = tookMillis
    }
}

// MARK: - Timeline

public struct TimelineRequest: Codable, Sendable, Equatable {
    public let from: Date
    public let to: Date
    public let bundleIDs: [String]?
    public let limit: Int?

    public init(from: Date, to: Date, bundleIDs: [String]? = nil, limit: Int? = nil) {
        self.from = from
        self.to = to
        self.bundleIDs = bundleIDs
        self.limit = limit
    }
}

public struct TimelineResponse: Codable, Sendable, Equatable {
    public let sessions: [ActivitySession]

    public init(sessions: [ActivitySession]) {
        self.sessions = sessions
    }
}

// MARK: - Events

public struct EventsRequest: Codable, Sendable, Equatable {
    public let from: Date
    public let to: Date
    public let source: ActivityEvent.Source?
    public let limit: Int?

    public init(
        from: Date,
        to: Date,
        source: ActivityEvent.Source? = nil,
        limit: Int? = nil
    ) {
        self.from = from
        self.to = to
        self.source = source
        self.limit = limit
    }
}

public struct EventsResponse: Codable, Sendable, Equatable {
    public let events: [ActivityEvent]

    public init(events: [ActivityEvent]) {
        self.events = events
    }
}

// MARK: - Rules

public struct RulesResponse: Codable, Sendable, Equatable {
    public let rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }
}

public struct AddRuleRequest: Codable, Sendable, Equatable {
    public let nl: String

    public init(nl: String) {
        self.nl = nl
    }
}

public struct AddRuleResponse: Codable, Sendable, Equatable {
    public let rule: Rule

    public init(rule: Rule) {
        self.rule = rule
    }
}

public struct ToggleRuleRequest: Codable, Sendable, Equatable {
    public let id: UUID
    public let enabled: Bool

    public init(id: UUID, enabled: Bool) {
        self.id = id
        self.enabled = enabled
    }
}

public struct DeleteRuleRequest: Codable, Sendable, Equatable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

// MARK: - Action controls

public struct KillAppRequest: Codable, Sendable, Equatable {
    public let bundleID: String
    public let strategy: Action.KillStrategy
    public let force: Bool
    public let confirmed: Bool

    public init(
        bundleID: String,
        strategy: Action.KillStrategy,
        force: Bool,
        confirmed: Bool
    ) {
        self.bundleID = bundleID
        self.strategy = strategy
        self.force = force
        self.confirmed = confirmed
    }
}

public struct KillAppResponse: Codable, Sendable, Equatable {
    public let outcome: String

    public init(outcome: String) {
        self.outcome = outcome
    }
}

public struct SetFocusRequest: Codable, Sendable, Equatable {
    public let mode: String?

    public init(mode: String?) {
        self.mode = mode
    }
}

// MARK: - Streaming

public struct TailRequest: Codable, Sendable, Equatable {
    public let sources: [ActivityEvent.Source]?

    public init(sources: [ActivityEvent.Source]? = nil) {
        self.sources = sources
    }
}

// MARK: - Void responses

/// Empty payload for calls that do not return anything meaningful on success.
public struct EmptyResponse: Codable, Sendable, Equatable {
    public init() {}
}
