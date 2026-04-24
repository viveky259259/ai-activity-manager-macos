import Foundation
import os
import ActivityCore

/// Typed async handler executed by the server for each incoming RPC.
///
/// The XPC listener decodes `Data` payloads into the strongly-typed DTOs declared
/// on this protocol, invokes the handler, then encodes the response back to `Data`.
/// Swap implementations in tests; wire to real use-cases in production.
public protocol IPCHandler: Sendable {
    func status() async throws -> StatusResponse
    func query(_ request: QueryRequest) async throws -> QueryResponse
    func timeline(_ request: TimelineRequest) async throws -> TimelineResponse
    func events(_ request: EventsRequest) async throws -> EventsResponse
    func rules() async throws -> RulesResponse
    func addRule(_ request: AddRuleRequest) async throws -> AddRuleResponse
    func toggleRule(_ request: ToggleRuleRequest) async throws -> EmptyResponse
    func deleteRule(_ request: DeleteRuleRequest) async throws -> EmptyResponse
    func killApp(_ request: KillAppRequest) async throws -> KillAppResponse
    func setFocusMode(_ request: SetFocusRequest) async throws -> EmptyResponse
}

/// Test double for `IPCHandler` that records calls and returns canned responses.
///
/// All mutable state is guarded by `OSAllocatedUnfairLock` so tests can assert from any
/// actor isolation context. The default responses return reasonable empty/zero values so
/// tests can override only what they care about.
public final class FakeIPCHandler: IPCHandler, @unchecked Sendable {
    public struct RecordedCalls: Sendable {
        public var status: Int = 0
        public var query: [QueryRequest] = []
        public var timeline: [TimelineRequest] = []
        public var events: [EventsRequest] = []
        public var rules: Int = 0
        public var addRule: [AddRuleRequest] = []
        public var toggleRule: [ToggleRuleRequest] = []
        public var deleteRule: [DeleteRuleRequest] = []
        public var killApp: [KillAppRequest] = []
        public var setFocusMode: [SetFocusRequest] = []
    }

    private struct State {
        var calls = RecordedCalls()

        // Stubbed responses.
        var statusResponse: StatusResponse = StatusResponse(
            sources: [],
            capturedEventCount: 0,
            actionsEnabled: false,
            permissions: [:]
        )
        var queryResponse: QueryResponse = QueryResponse(
            answer: "",
            cited: [],
            provider: "fake",
            tookMillis: 0
        )
        var timelineResponse: TimelineResponse = TimelineResponse(sessions: [])
        var eventsResponse: EventsResponse = EventsResponse(events: [])
        var rulesResponse: RulesResponse = RulesResponse(rules: [])
        var addRuleResponse: AddRuleResponse?
        var killAppResponse: KillAppResponse = KillAppResponse(outcome: "succeeded")

        // Error injection — if set, the matching method throws.
        var statusError: IPCError?
        var queryError: IPCError?
        var timelineError: IPCError?
        var eventsError: IPCError?
        var rulesError: IPCError?
        var addRuleError: IPCError?
        var toggleRuleError: IPCError?
        var deleteRuleError: IPCError?
        var killAppError: IPCError?
        var setFocusError: IPCError?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    // MARK: Stubbing

    public var calls: RecordedCalls { state.withLock { $0.calls } }

    public func setStatusResponse(_ r: StatusResponse) {
        state.withLock { $0.statusResponse = r }
    }
    public func setQueryResponse(_ r: QueryResponse) {
        state.withLock { $0.queryResponse = r }
    }
    public func setTimelineResponse(_ r: TimelineResponse) {
        state.withLock { $0.timelineResponse = r }
    }
    public func setEventsResponse(_ r: EventsResponse) {
        state.withLock { $0.eventsResponse = r }
    }
    public func setRulesResponse(_ r: RulesResponse) {
        state.withLock { $0.rulesResponse = r }
    }
    public func setAddRuleResponse(_ r: AddRuleResponse) {
        state.withLock { $0.addRuleResponse = r }
    }
    public func setKillAppResponse(_ r: KillAppResponse) {
        state.withLock { $0.killAppResponse = r }
    }

    public func stubError(forStatus e: IPCError?) { state.withLock { $0.statusError = e } }
    public func stubError(forQuery e: IPCError?) { state.withLock { $0.queryError = e } }
    public func stubError(forTimeline e: IPCError?) { state.withLock { $0.timelineError = e } }
    public func stubError(forEvents e: IPCError?) { state.withLock { $0.eventsError = e } }
    public func stubError(forRules e: IPCError?) { state.withLock { $0.rulesError = e } }
    public func stubError(forAddRule e: IPCError?) { state.withLock { $0.addRuleError = e } }
    public func stubError(forToggleRule e: IPCError?) { state.withLock { $0.toggleRuleError = e } }
    public func stubError(forDeleteRule e: IPCError?) { state.withLock { $0.deleteRuleError = e } }
    public func stubError(forKillApp e: IPCError?) { state.withLock { $0.killAppError = e } }
    public func stubError(forSetFocus e: IPCError?) { state.withLock { $0.setFocusError = e } }

    // MARK: IPCHandler

    public func status() async throws -> StatusResponse {
        try state.withLock { s throws -> StatusResponse in
            s.calls.status += 1
            if let e = s.statusError { throw e }
            return s.statusResponse
        }
    }

    public func query(_ request: QueryRequest) async throws -> QueryResponse {
        try state.withLock { s throws -> QueryResponse in
            s.calls.query.append(request)
            if let e = s.queryError { throw e }
            return s.queryResponse
        }
    }

    public func timeline(_ request: TimelineRequest) async throws -> TimelineResponse {
        try state.withLock { s throws -> TimelineResponse in
            s.calls.timeline.append(request)
            if let e = s.timelineError { throw e }
            return s.timelineResponse
        }
    }

    public func events(_ request: EventsRequest) async throws -> EventsResponse {
        try state.withLock { s throws -> EventsResponse in
            s.calls.events.append(request)
            if let e = s.eventsError { throw e }
            return s.eventsResponse
        }
    }

    public func rules() async throws -> RulesResponse {
        try state.withLock { s throws -> RulesResponse in
            s.calls.rules += 1
            if let e = s.rulesError { throw e }
            return s.rulesResponse
        }
    }

    public func addRule(_ request: AddRuleRequest) async throws -> AddRuleResponse {
        try state.withLock { s throws -> AddRuleResponse in
            s.calls.addRule.append(request)
            if let e = s.addRuleError { throw e }
            if let stubbed = s.addRuleResponse { return stubbed }
            // Fall back to a synthesised rule so tests that forget to stub still work.
            let rule = Rule(
                name: "fake",
                nlSource: request.nl,
                trigger: .appFocused(bundleID: "unknown", durationAtLeast: nil),
                actions: [.logMessage(request.nl)],
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0)
            )
            return AddRuleResponse(rule: rule)
        }
    }

    public func toggleRule(_ request: ToggleRuleRequest) async throws -> EmptyResponse {
        try state.withLock { s throws -> EmptyResponse in
            s.calls.toggleRule.append(request)
            if let e = s.toggleRuleError { throw e }
            return EmptyResponse()
        }
    }

    public func deleteRule(_ request: DeleteRuleRequest) async throws -> EmptyResponse {
        try state.withLock { s throws -> EmptyResponse in
            s.calls.deleteRule.append(request)
            if let e = s.deleteRuleError { throw e }
            return EmptyResponse()
        }
    }

    public func killApp(_ request: KillAppRequest) async throws -> KillAppResponse {
        try state.withLock { s throws -> KillAppResponse in
            s.calls.killApp.append(request)
            if let e = s.killAppError { throw e }
            return s.killAppResponse
        }
    }

    public func setFocusMode(_ request: SetFocusRequest) async throws -> EmptyResponse {
        try state.withLock { s throws -> EmptyResponse in
            s.calls.setFocusMode.append(request)
            if let e = s.setFocusError { throw e }
            return EmptyResponse()
        }
    }
}
