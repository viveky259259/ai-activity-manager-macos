import Foundation

public struct Rule: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var nlSource: String
    public var trigger: Trigger
    public var condition: Condition?
    public var actions: [Action]
    public var mode: Mode
    public var confirm: ConfirmPolicy
    public var cooldown: TimeInterval
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        nlSource: String,
        trigger: Trigger,
        condition: Condition? = nil,
        actions: [Action],
        mode: Mode = .dryRun,
        confirm: ConfirmPolicy = .never,
        cooldown: TimeInterval = 60,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.nlSource = nlSource
        self.trigger = trigger
        self.condition = condition
        self.actions = actions
        self.mode = mode
        self.confirm = confirm
        self.cooldown = cooldown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public enum Mode: String, Hashable, Sendable, Codable {
        case dryRun
        case active
        case disabled
    }

    public enum ConfirmPolicy: String, Hashable, Sendable, Codable {
        case never
        case once
        case always
    }
}

public enum Trigger: Hashable, Sendable, Codable {
    case appFocused(bundleID: String, durationAtLeast: TimeInterval?)
    case appFocusLost(bundleID: String)
    case urlHostVisited(host: String, durationAtLeast: TimeInterval?)
    case idleEntered(after: TimeInterval)
    case idleEnded
    case calendarEventStarted(titleMatches: String?)
    case calendarEventEnded(titleMatches: String?)
    case focusModeChanged(to: String?)
    case timeOfDay(hour: Int, minute: Int, weekdays: Set<Int>)

    public var kind: Kind {
        switch self {
        case .appFocused: return .appFocused
        case .appFocusLost: return .appFocusLost
        case .urlHostVisited: return .urlHostVisited
        case .idleEntered: return .idleEntered
        case .idleEnded: return .idleEnded
        case .calendarEventStarted: return .calendarEventStarted
        case .calendarEventEnded: return .calendarEventEnded
        case .focusModeChanged: return .focusModeChanged
        case .timeOfDay: return .timeOfDay
        }
    }

    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case appFocused
        case appFocusLost
        case urlHostVisited
        case idleEntered
        case idleEnded
        case calendarEventStarted
        case calendarEventEnded
        case focusModeChanged
        case timeOfDay
    }
}

public indirect enum Condition: Hashable, Sendable, Codable {
    case and([Condition])
    case or([Condition])
    case not(Condition)
    case focusModeIs(String?)
    case betweenHours(start: Int, end: Int)
    case weekday(Set<Int>)
    case custom(key: String, op: CompareOp, value: String)

    public enum CompareOp: String, Hashable, Sendable, Codable {
        case eq, neq, gt, lt, gte, lte, contains, matches
    }
}

public enum Action: Hashable, Sendable, Codable {
    case setFocusMode(name: String?)
    case killApp(bundleID: String, strategy: KillStrategy, force: Bool)
    case launchApp(bundleID: String)
    case postNotification(title: String, body: String)
    case runShortcut(name: String)
    case logMessage(String)

    public enum KillStrategy: String, Hashable, Sendable, Codable {
        case politeQuit
        case forceQuit
        case signal
    }
}
