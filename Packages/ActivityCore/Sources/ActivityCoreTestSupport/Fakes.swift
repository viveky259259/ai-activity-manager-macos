import Foundation
import os
import ActivityCore

public final class FakeClock: Clock, Sendable {
    private let state: OSAllocatedUnfairLock<Date>

    public init(_ initial: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.state = OSAllocatedUnfairLock(initialState: initial)
    }

    public func now() -> Date {
        state.withLock { $0 }
    }

    public func advance(_ interval: TimeInterval) {
        state.withLock { $0 = $0.addingTimeInterval(interval) }
    }

    public func set(_ date: Date) {
        state.withLock { $0 = date }
    }
}

public final class FakeStore: ActivityStore, Sendable {
    private struct State {
        var events: [ActivityEvent] = []
        var rules: [UUID: Rule] = [:]
        var appendCalls: Int = 0
        var appendError: (any Error)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public var storedEvents: [ActivityEvent] {
        state.withLock { $0.events }
    }

    public var appendCalls: Int {
        state.withLock { $0.appendCalls }
    }

    public func setAppendError(_ error: (any Error)?) {
        state.withLock { $0.appendError = error }
    }

    public func append(_ events: [ActivityEvent]) async throws {
        try state.withLock { s throws in
            s.appendCalls += 1
            if let err = s.appendError { throw err }
            s.events.append(contentsOf: events)
        }
    }

    public func events(in range: DateInterval, limit: Int?) async throws -> [ActivityEvent] {
        state.withLock { s in
            var filtered = s.events.filter { range.contains($0.timestamp) }
            filtered.sort(by: Self.order)
            if let limit { return Array(filtered.prefix(limit)) }
            return filtered
        }
    }

    public func search(_ query: TimelineQuery) async throws -> [ActivityEvent] {
        state.withLock { s in
            var filtered = s.events.filter { query.range.contains($0.timestamp) }
            if let sources = query.sources { filtered = filtered.filter { sources.contains($0.source) } }
            if let bundles = query.bundleIDs {
                filtered = filtered.filter { e in
                    if case .app(let id, _) = e.subject { return bundles.contains(id) }
                    return false
                }
            }
            if let host = query.hostContains {
                filtered = filtered.filter { e in
                    if case .url(let h, _) = e.subject { return h.contains(host) }
                    return false
                }
            }
            if let ft = query.fullText {
                filtered = filtered.filter { e in
                    if case .app(_, let name) = e.subject { return name.localizedCaseInsensitiveContains(ft) }
                    if case .url(_, let path) = e.subject { return path.localizedCaseInsensitiveContains(ft) }
                    if case .calendarEvent(_, let title) = e.subject { return title.localizedCaseInsensitiveContains(ft) }
                    return e.attributes.values.contains { $0.localizedCaseInsensitiveContains(ft) }
                }
            }
            filtered.sort(by: Self.order)
            if let limit = query.limit { return Array(filtered.prefix(limit)) }
            return filtered
        }
    }

    public func sessions(in range: DateInterval, gapThreshold: TimeInterval) async throws -> [ActivitySession] {
        let e = try await events(in: range, limit: nil)
        return SessionCollapser().collapse(e, gapThreshold: gapThreshold)
    }

    public func rules() async throws -> [Rule] {
        state.withLock { Array($0.rules.values).sorted { $0.createdAt < $1.createdAt } }
    }

    public func upsertRule(_ rule: Rule) async throws {
        state.withLock { $0.rules[rule.id] = rule }
    }

    public func deleteRule(id: UUID) async throws {
        state.withLock { _ = $0.rules.removeValue(forKey: id) }
    }

    private static func order(_ a: ActivityEvent, _ b: ActivityEvent) -> Bool {
        if a.timestamp == b.timestamp { return a.id.uuidString < b.id.uuidString }
        return a.timestamp < b.timestamp
    }
}

public final class FakeLLMProvider: LLMProvider, Sendable {
    public let identifier: String
    public let isLocal: Bool

    private struct State {
        var stubs: [@Sendable (LLMRequest) -> Result<LLMResponse, any Error>] = []
        var callCount: Int = 0
        var lastRequest: LLMRequest?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(identifier: String = "fake", isLocal: Bool = true) {
        self.identifier = identifier
        self.isLocal = isLocal
    }

    public var requestCount: Int {
        state.withLock { $0.callCount }
    }

    public var capturedRequest: LLMRequest? {
        state.withLock { $0.lastRequest }
    }

    public func stubText(_ text: String) {
        let model = identifier
        stub { _ in
            .success(LLMResponse(text: text, inputTokens: 10, outputTokens: text.count / 4, model: model))
        }
    }

    public func stubJSON(_ json: String) {
        stubText(json)
    }

    public func stubError(_ error: any Error) {
        let boxed = ErrorBox(error)
        stub { _ in .failure(boxed.error) }
    }

    public func stub(_ handler: @Sendable @escaping (LLMRequest) -> Result<LLMResponse, any Error>) {
        state.withLock { $0.stubs.append(handler) }
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let next: (@Sendable (LLMRequest) -> Result<LLMResponse, any Error>)? = state.withLock { s in
            s.callCount += 1
            s.lastRequest = request
            guard !s.stubs.isEmpty else { return nil }
            return s.stubs.removeFirst()
        }
        guard let next else {
            return LLMResponse(text: "", inputTokens: 0, outputTokens: 0, model: identifier)
        }
        switch next(request) {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}

private struct ErrorBox: @unchecked Sendable {
    let error: any Error
    init(_ error: any Error) { self.error = error }
}

public final class FakeExecutor: ActionExecutor, Sendable {
    private struct State {
        var executed: [Action] = []
        var handler: @Sendable (Action) -> ActionOutcome
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(outcome: @Sendable @escaping (Action) -> ActionOutcome = { _ in .succeeded }) {
        self.state = OSAllocatedUnfairLock(initialState: State(handler: outcome))
    }

    public var executedActions: [Action] {
        state.withLock { $0.executed }
    }

    public func setOutcome(_ handler: @Sendable @escaping (Action) -> ActionOutcome) {
        state.withLock { $0.handler = handler }
    }

    public func execute(_ action: Action) async throws -> ActionOutcome {
        state.withLock { s in
            s.executed.append(action)
            return s.handler(action)
        }
    }
}

public enum Fixtures {
    public static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    public static func frontmost(
        bundleID: String,
        name: String,
        at t: TimeInterval,
        base: Date = epoch
    ) -> ActivityEvent {
        ActivityEvent(
            timestamp: base.addingTimeInterval(t),
            source: .frontmost,
            subject: .app(bundleID: bundleID, name: name)
        )
    }

    public static func url(
        host: String,
        path: String = "/",
        at t: TimeInterval,
        base: Date = epoch
    ) -> ActivityEvent {
        ActivityEvent(
            timestamp: base.addingTimeInterval(t),
            source: .frontmost,
            subject: .url(host: host, path: path)
        )
    }

    public static func idle(
        transition: String,
        at t: TimeInterval,
        base: Date = epoch
    ) -> ActivityEvent {
        ActivityEvent(
            timestamp: base.addingTimeInterval(t),
            source: .idle,
            subject: .idleSpan(startedAt: base.addingTimeInterval(t), endedAt: base.addingTimeInterval(t)),
            attributes: ["idleTransition": transition]
        )
    }

    public static func rule(
        name: String = "test rule",
        trigger: Trigger,
        actions: [Action],
        mode: Rule.Mode = .active,
        cooldown: TimeInterval = 60,
        now: Date = epoch
    ) -> Rule {
        Rule(
            name: name,
            nlSource: name,
            trigger: trigger,
            condition: nil,
            actions: actions,
            mode: mode,
            confirm: .never,
            cooldown: cooldown,
            createdAt: now,
            updatedAt: now
        )
    }
}
