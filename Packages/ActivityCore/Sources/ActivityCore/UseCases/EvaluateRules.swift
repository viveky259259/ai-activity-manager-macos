import Foundation

public actor EvaluateRules {
    public struct Dispatch: Hashable, Sendable {
        public let ruleID: UUID
        public let action: Action
        public let outcome: ActionOutcome
        public let firedAt: Date
    }

    private let executor: ActionExecutor
    private let clock: Clock
    private var rules: [Rule] = []
    private var rulesByKind: [Trigger.Kind: [UUID]] = [:]
    private var lastFired: [UUID: Date] = [:]

    public init(executor: ActionExecutor, clock: Clock) {
        self.executor = executor
        self.clock = clock
    }

    public func load(_ rules: [Rule]) {
        self.rules = rules
        rulesByKind.removeAll(keepingCapacity: true)
        for rule in rules where rule.mode != .disabled {
            rulesByKind[rule.trigger.kind, default: []].append(rule.id)
        }
    }

    public func handle(_ event: ActivityEvent) async -> [Dispatch] {
        let kind = Self.triggerKind(for: event)
        guard let kind,
              let ruleIDs = rulesByKind[kind] else { return [] }
        var results: [Dispatch] = []
        let now = clock.now()
        for id in ruleIDs {
            guard let rule = rules.first(where: { $0.id == id }) else { continue }
            guard Self.triggerMatches(rule.trigger, event: event) else { continue }
            if let condition = rule.condition,
               !Self.conditionMatches(condition, event: event, now: now) { continue }
            if let last = lastFired[rule.id], now.timeIntervalSince(last) < rule.cooldown {
                continue
            }
            lastFired[rule.id] = now
            for action in rule.actions {
                let outcome: ActionOutcome
                if rule.mode == .dryRun {
                    outcome = .dryRun(description: Self.describe(action))
                } else {
                    do {
                        outcome = try await executor.execute(action)
                    } catch {
                        outcome = .refused(reason: String(describing: error))
                    }
                }
                results.append(Dispatch(ruleID: rule.id, action: action, outcome: outcome, firedAt: now))
            }
        }
        return results
    }

    static func triggerKind(for event: ActivityEvent) -> Trigger.Kind? {
        switch event.source {
        case .frontmost:
            if case .app = event.subject { return .appFocused }
            if case .url = event.subject { return .urlHostVisited }
            return nil
        case .idle:
            if let marker = event.attributes["idleTransition"] {
                return marker == "entered" ? .idleEntered : .idleEnded
            }
            return nil
        case .calendar:
            if let phase = event.attributes["phase"] {
                return phase == "started" ? .calendarEventStarted : .calendarEventEnded
            }
            return nil
        case .focusMode: return .focusModeChanged
        case .screenshot, .rule, .mcp, .cli: return nil
        }
    }

    static func triggerMatches(_ trigger: Trigger, event: ActivityEvent) -> Bool {
        switch trigger {
        case .appFocused(let bundleID, _):
            if case .app(let id, _) = event.subject { return id == bundleID }
            return false
        case .appFocusLost(let bundleID):
            return event.attributes["lostFocus"] == bundleID
        case .urlHostVisited(let host, _):
            if case .url(let h, _) = event.subject { return h == host || h.hasSuffix("." + host) }
            return false
        case .idleEntered: return event.attributes["idleTransition"] == "entered"
        case .idleEnded: return event.attributes["idleTransition"] == "ended"
        case .calendarEventStarted(let match):
            guard event.attributes["phase"] == "started" else { return false }
            return matches(match, to: event)
        case .calendarEventEnded(let match):
            guard event.attributes["phase"] == "ended" else { return false }
            return matches(match, to: event)
        case .focusModeChanged(let to):
            if case .focusMode(let name) = event.subject { return to == nil || name == to }
            return false
        case .timeOfDay: return false
        }
    }

    private static func matches(_ pattern: String?, to event: ActivityEvent) -> Bool {
        guard let pattern, !pattern.isEmpty else { return true }
        if case .calendarEvent(_, let title) = event.subject {
            return title.range(of: pattern, options: .regularExpression) != nil
        }
        return false
    }

    static func conditionMatches(_ condition: Condition, event: ActivityEvent, now: Date) -> Bool {
        switch condition {
        case .and(let conds): return conds.allSatisfy { conditionMatches($0, event: event, now: now) }
        case .or(let conds): return conds.contains { conditionMatches($0, event: event, now: now) }
        case .not(let c): return !conditionMatches(c, event: event, now: now)
        case .focusModeIs(let name):
            return event.attributes["focusMode"] == (name ?? "")
        case .betweenHours(let start, let end):
            let hour = Calendar.current.component(.hour, from: now)
            if start <= end { return hour >= start && hour < end }
            return hour >= start || hour < end
        case .weekday(let days):
            let wd = Calendar.current.component(.weekday, from: now)
            return days.contains(wd)
        case .custom(let key, let op, let value):
            let lhs = event.attributes[key] ?? ""
            return compare(lhs, op, value)
        }
    }

    static func compare(_ lhs: String, _ op: Condition.CompareOp, _ rhs: String) -> Bool {
        switch op {
        case .eq: return lhs == rhs
        case .neq: return lhs != rhs
        case .contains: return lhs.contains(rhs)
        case .matches: return lhs.range(of: rhs, options: .regularExpression) != nil
        case .gt, .lt, .gte, .lte:
            guard let l = Double(lhs), let r = Double(rhs) else { return false }
            switch op {
            case .gt: return l > r
            case .lt: return l < r
            case .gte: return l >= r
            case .lte: return l <= r
            default: return false
            }
        }
    }

    static func describe(_ action: Action) -> String {
        switch action {
        case .setFocusMode(let name): return "setFocusMode(\(name ?? "off"))"
        case .killApp(let id, let s, let f): return "killApp(\(id), \(s.rawValue), force=\(f))"
        case .launchApp(let id): return "launchApp(\(id))"
        case .postNotification(let t, _): return "postNotification(\(t))"
        case .runShortcut(let n): return "runShortcut(\(n))"
        case .logMessage(let m): return "logMessage(\(m))"
        }
    }
}
