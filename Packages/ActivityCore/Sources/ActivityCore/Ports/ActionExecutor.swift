import Foundation

public protocol ActionExecutor: Sendable {
    func execute(_ action: Action) async throws -> ActionOutcome
}

public enum ActionOutcome: Hashable, Sendable, Codable {
    case succeeded
    case refused(reason: String)
    case notPermitted(reason: String)
    case escalated(previous: String)
    case dryRun(description: String)
}

public enum ActionError: Error, Sendable, Equatable {
    case globallyDisabled
    case cooldown(until: Date)
    case invalidTarget(String)
    case internalFailure(String)
}
