import Foundation
import ActivityCore
import ActivityStore
import ActivityIPC
import ActivityActions
import ActivityMCP
import ActivityCapture

/// Production `IPCHandler` used by the menu-bar daemon. Routes every RPC to
/// the real subsystems (store, process terminator, live sampler, permissions
/// checker) so XPC clients — including `activity-mcp` — see the same state
/// the UI does.
///
/// Deliberately free of logic that belongs in use-cases: filtering / sorting /
/// categorization live in ``ProcessesQueryApplier`` and ``AppCategoryCatalog``
/// so they can be unit-tested without spinning up an XPC loop.
public final class ProductionIPCHandler: IPCHandler, @unchecked Sendable {

    private let store: any ActivityStore
    private let terminator: ProcessTerminator
    private let sampler: any SystemProcessSampler
    private let categories: AppCategoryCatalog
    private let memorySource: @Sendable () -> SystemMemorySource.Snapshot?
    private let permissions: any PermissionsChecker
    private let captureStatuses: @Sendable () -> [String: SourceStatus]
    private let clock: @Sendable () -> Date

    public init(
        store: any ActivityStore,
        terminator: ProcessTerminator,
        sampler: any SystemProcessSampler,
        permissions: any PermissionsChecker,
        memorySource: @escaping @Sendable () -> SystemMemorySource.Snapshot?,
        categories: AppCategoryCatalog = .shared,
        captureStatuses: @escaping @Sendable () -> [String: SourceStatus] = { [:] },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.terminator = terminator
        self.sampler = sampler
        self.categories = categories
        self.memorySource = memorySource
        self.permissions = permissions
        self.captureStatuses = captureStatuses
        self.clock = clock
    }

    // MARK: - Status / metadata

    public func status() async throws -> StatusResponse {
        let sources = Array(captureStatuses().keys).sorted()
        let perms: [Permission] = [.accessibility, .calendar, .focus]
        var dict: [String: String] = [:]
        for p in perms {
            let key: String
            switch p {
            case .accessibility: key = "accessibility"
            case .calendar:      key = "calendar"
            case .focus:         key = "focus"
            case .automation:    key = "automation"
            }
            dict[key] = permissions.status(for: p).rawValue
        }
        return StatusResponse(
            sources: sources,
            capturedEventCount: 0,
            actionsEnabled: terminator.actionsEnabled,
            permissions: dict
        )
    }

    // MARK: - Timeline / events

    public func timeline(_ request: TimelineRequest) async throws -> TimelineResponse {
        let range = DateInterval(start: request.from, end: max(request.from, request.to))
        let all = try await store.sessions(in: range, gapThreshold: 300)
        let filtered: [ActivitySession]
        if let bundles = request.bundleIDs, !bundles.isEmpty {
            let set = Set(bundles)
            filtered = all.filter { session in
                if case let .app(bundleID, _) = session.subject {
                    return set.contains(bundleID)
                }
                return false
            }
        } else {
            filtered = all
        }
        if let limit = request.limit, limit > 0, filtered.count > limit {
            return TimelineResponse(sessions: Array(filtered.prefix(limit)))
        }
        return TimelineResponse(sessions: filtered)
    }

    public func events(_ request: EventsRequest) async throws -> EventsResponse {
        let range = DateInterval(start: request.from, end: max(request.from, request.to))
        let sources: Set<ActivityEvent.Source>? = request.source.map { Set([$0]) }
        let query = TimelineQuery(
            range: range,
            sources: sources,
            bundleIDs: nil,
            hostContains: nil,
            fullText: nil,
            limit: request.limit
        )
        let events = try await store.search(query)
        return EventsResponse(events: events)
    }

    // MARK: - Query (NL) — not implemented yet

    public func query(_ request: QueryRequest) async throws -> QueryResponse {
        QueryResponse(
            answer: "",
            cited: [],
            provider: "none",
            tookMillis: 0
        )
    }

    // MARK: - Rules

    public func rules() async throws -> RulesResponse {
        let rules = try await store.rules()
        return RulesResponse(rules: rules)
    }

    public func addRule(_ request: AddRuleRequest) async throws -> AddRuleResponse {
        throw IPCError(code: "not_implemented", message: "rule compilation from NL is not wired yet")
    }

    public func toggleRule(_ request: ToggleRuleRequest) async throws -> EmptyResponse {
        let current = try await store.rules()
        guard var rule = current.first(where: { $0.id == request.id }) else {
            throw IPCError(code: "not_found", message: "no rule with id \(request.id)")
        }
        rule.mode = request.enabled ? .active : .disabled
        rule.updatedAt = clock()
        try await store.upsertRule(rule)
        return EmptyResponse()
    }

    public func deleteRule(_ request: DeleteRuleRequest) async throws -> EmptyResponse {
        try await store.deleteRule(id: request.id)
        return EmptyResponse()
    }

    // MARK: - Actions

    public func killApp(_ request: KillAppRequest) async throws -> KillAppResponse {
        guard request.hasExactlyOneTarget else {
            throw IPCError(
                code: IPCError.invalidRequest.code,
                message: "exactly one of bundle_id or pid is required"
            )
        }

        let outcome: ActionOutcome
        if let pid = request.pid {
            outcome = await terminator.killProcess(
                pid: pid,
                strategy: request.strategy,
                force: request.force
            )
        } else if let bundle = request.bundleID {
            outcome = try await terminator.execute(
                .killApp(bundleID: bundle, strategy: request.strategy, force: request.force)
            )
        } else {
            throw IPCError.invalidRequest
        }
        return KillAppResponse(outcome: encode(outcome: outcome))
    }

    public func setFocusMode(_ request: SetFocusRequest) async throws -> EmptyResponse {
        throw IPCError(
            code: "not_implemented",
            message: "focus mode control is not wired yet"
        )
    }

    // MARK: - Processes

    public func listProcesses(_ request: ProcessesQuery) async throws -> ProcessesPage {
        let raw = sampler.capture()
        let snapshots: [ProcessSnapshot] = raw.map { s in
            ProcessSnapshot(
                pid: s.pid,
                bundleID: s.bundleID,
                name: s.name,
                user: s.user,
                memoryBytes: s.memoryBytes,
                cpuPercent: 0,
                threads: s.threads,
                isFrontmost: false,
                isRestricted: s.isRestricted,
                category: categories.category(for: s.bundleID)
            )
        }
        let filtered = ProcessesQueryApplier.apply(request, to: snapshots)
        let mem = memorySource()
        return ProcessesPage(
            processes: filtered,
            systemMemoryUsedBytes: mem?.usedBytes,
            systemMemoryTotalBytes: mem?.totalBytes,
            sampledAt: clock()
        )
    }

    // MARK: - Helpers

    private func encode(outcome: ActionOutcome) -> String {
        switch outcome {
        case .succeeded: return "succeeded"
        case .refused(let reason): return "refused:\(reason)"
        case .notPermitted(let reason): return "not_permitted:\(reason)"
        case .escalated(let previous): return "escalated:\(previous)"
        case .dryRun(let description): return "dry_run:\(description)"
        }
    }
}
