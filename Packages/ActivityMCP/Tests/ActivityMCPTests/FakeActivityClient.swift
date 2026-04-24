import Foundation
import os
import ActivityCore
import ActivityIPC
@testable import ActivityMCP

/// Thread-safe fake `ActivityClientProtocol` for unit tests.
final class FakeActivityClient: ActivityClientProtocol, @unchecked Sendable {
    /// Dispatch counters the rate-limit tests read before/after a request to
    /// confirm the handler gated the second call without hitting the client.
    struct Calls: Sendable {
        var status: Int = 0
        var killApp: [KillAppRequest] = []
    }

    struct State {
        var calls: Calls = Calls()
        var statusResponse: StatusResponse = StatusResponse(
            sources: ["frontmost"],
            capturedEventCount: 0,
            actionsEnabled: false,
            permissions: [:]
        )
        var timelineResponse: TimelineResponse = TimelineResponse(sessions: [])
        var eventsResponse: EventsResponse = EventsResponse(events: [])
        var rulesResponse: RulesResponse = RulesResponse(rules: [])
        var addRuleResponse: AddRuleResponse?
        var killAppResponse: KillAppResponse = KillAppResponse(outcome: "killed")
        var listProcessesResponse: ProcessesPage = ProcessesPage(
            processes: [],
            systemMemoryUsedBytes: nil,
            systemMemoryTotalBytes: nil,
            sampledAt: Date(timeIntervalSince1970: 0)
        )

        var capturedTimelineRequest: TimelineRequest?
        var capturedEventsRequest: EventsRequest?
        var capturedAddRuleRequest: AddRuleRequest?
        var capturedToggleRuleRequest: ToggleRuleRequest?
        var capturedKillAppRequest: KillAppRequest?
        var capturedSetFocusRequest: SetFocusRequest?
        var capturedListProcessesRequest: ProcessesQuery?

        var statusError: (any Error)?
        var timelineError: (any Error)?
        var eventsError: (any Error)?
        var rulesError: (any Error)?
        var addRuleError: (any Error)?
        var toggleRuleError: (any Error)?
        var killAppError: (any Error)?
        var setFocusError: (any Error)?
        var listProcessesError: (any Error)?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    init() {}

    // Configuration helpers (tests only)
    func setStatus(_ response: StatusResponse) { lock.withLock { $0.statusResponse = response } }
    func setTimeline(_ response: TimelineResponse) { lock.withLock { $0.timelineResponse = response } }
    func setEvents(_ response: EventsResponse) { lock.withLock { $0.eventsResponse = response } }
    func setRules(_ response: RulesResponse) { lock.withLock { $0.rulesResponse = response } }
    func setAddRule(_ response: AddRuleResponse) { lock.withLock { $0.addRuleResponse = response } }
    func setKillApp(_ response: KillAppResponse) { lock.withLock { $0.killAppResponse = response } }
    func setListProcesses(_ response: ProcessesPage) { lock.withLock { $0.listProcessesResponse = response } }

    var capturedTimelineRequest: TimelineRequest? { lock.withLock { $0.capturedTimelineRequest } }
    var capturedEventsRequest: EventsRequest? { lock.withLock { $0.capturedEventsRequest } }
    var capturedAddRuleRequest: AddRuleRequest? { lock.withLock { $0.capturedAddRuleRequest } }
    var capturedToggleRuleRequest: ToggleRuleRequest? { lock.withLock { $0.capturedToggleRuleRequest } }
    var capturedKillAppRequest: KillAppRequest? { lock.withLock { $0.capturedKillAppRequest } }
    var capturedSetFocusRequest: SetFocusRequest? { lock.withLock { $0.capturedSetFocusRequest } }
    var capturedListProcessesRequest: ProcessesQuery? { lock.withLock { $0.capturedListProcessesRequest } }
    var calls: Calls { lock.withLock { $0.calls } }

    // MARK: ActivityClientProtocol

    func status() async throws -> StatusResponse {
        try lock.withLock { s in
            s.calls.status += 1
            if let e = s.statusError { throw e }
            return s.statusResponse
        }
    }

    func timeline(_ request: TimelineRequest) async throws -> TimelineResponse {
        try lock.withLock { s in
            s.capturedTimelineRequest = request
            if let e = s.timelineError { throw e }
            return s.timelineResponse
        }
    }

    func events(_ request: EventsRequest) async throws -> EventsResponse {
        try lock.withLock { s in
            s.capturedEventsRequest = request
            if let e = s.eventsError { throw e }
            return s.eventsResponse
        }
    }

    func rules() async throws -> RulesResponse {
        try lock.withLock { s in
            if let e = s.rulesError { throw e }
            return s.rulesResponse
        }
    }

    func addRule(_ request: AddRuleRequest) async throws -> AddRuleResponse {
        try lock.withLock { s in
            s.capturedAddRuleRequest = request
            if let e = s.addRuleError { throw e }
            if let r = s.addRuleResponse { return r }
            // Default synthesized response
            let rule = Rule(
                name: "proposed",
                nlSource: request.nl,
                trigger: .idleEnded,
                condition: nil,
                actions: [.logMessage("noop")],
                mode: .dryRun,
                confirm: .never,
                cooldown: 60,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            return AddRuleResponse(rule: rule)
        }
    }

    func toggleRule(_ request: ToggleRuleRequest) async throws {
        try lock.withLock { s in
            s.capturedToggleRuleRequest = request
            if let e = s.toggleRuleError { throw e }
        }
    }

    func killApp(_ request: KillAppRequest) async throws -> KillAppResponse {
        try lock.withLock { s in
            s.capturedKillAppRequest = request
            s.calls.killApp.append(request)
            if let e = s.killAppError { throw e }
            return s.killAppResponse
        }
    }

    func setFocusMode(_ request: SetFocusRequest) async throws {
        try lock.withLock { s in
            s.capturedSetFocusRequest = request
            if let e = s.setFocusError { throw e }
        }
    }

    func listProcesses(_ request: ProcessesQuery) async throws -> ProcessesPage {
        try lock.withLock { s in
            s.capturedListProcessesRequest = request
            if let e = s.listProcessesError { throw e }
            return s.listProcessesResponse
        }
    }
}
