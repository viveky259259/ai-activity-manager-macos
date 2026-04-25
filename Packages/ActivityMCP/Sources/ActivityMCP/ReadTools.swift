import Foundation
import ActivityCore
import ActivityIPC

/// Factory for the read-only MCP tools. Each tool is wired to an
/// `ActivityClientProtocol` so production (IPCClient) and tests
/// (FakeActivityClient) share the same handler code.
public enum ReadTools {
    public static func make(client: any ActivityClientProtocol) -> [ToolDefinition] {
        [
            currentActivity(client: client),
            timelineRange(client: client),
            timelineQuery(client: client),
            eventsSearch(client: client),
            appUsage(client: client),
            listRules(client: client),
            ruleExplain(client: client),
            listProcesses(client: client),
            recentProjects(client: client),
            timePerRepo(client: client),
            filesTouched(client: client),
            currentContext(client: client),
        ]
    }

    // MARK: current_activity

    private static func currentActivity(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "current_activity",
            description: "Returns the frontmost app, session duration, focus mode, and idle state.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { _ in
                let status = try await client.status()
                return .object([
                    "sources": .array(status.sources.map { .string($0) }),
                    "captured_event_count": .int(status.capturedEventCount),
                    "actions_enabled": .bool(status.actionsEnabled),
                    "permissions": .object(status.permissions.mapValues { .string($0) }),
                    "schema_version": .int(1),
                ])
            }
        )
    }

    // MARK: timeline_range

    private static func timelineRange(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "timeline_range",
            description: "Return collapsed activity sessions between two timestamps.",
            inputSchema: .object([
                "type": .string("object"),
                "required": .array([.string("from"), .string("to")]),
                "properties": .object([
                    "from": .object(["type": .string("string"), "format": .string("date-time")]),
                    "to": .object(["type": .string("string"), "format": .string("date-time")]),
                    "app_filter": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                    "limit": .object(["type": .string("integer")]),
                ]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { args in
                guard let from = JSONBridge.parseDate(args["from"]),
                      let to = JSONBridge.parseDate(args["to"]) else {
                    throw JSONRPCError.invalidParams
                }
                let bundleIDs = args["app_filter"]?.arrayValue?.compactMap { $0.stringValue }
                let limit = args["limit"]?.intValue
                let req = TimelineRequest(
                    from: from,
                    to: to,
                    bundleIDs: (bundleIDs?.isEmpty == false) ? bundleIDs : nil,
                    limit: limit
                )
                let resp = try await client.timeline(req)
                return try JSONBridge.encode(resp)
            }
        )
    }

    // MARK: timeline_query (not implemented yet)

    private static func timelineQuery(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "timeline_query",
            description: "Answer a natural-language question about the timeline.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "question": .object(["type": .string("string")]),
                    "time_hint": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("question")]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { _ in
                .object(["message": .string("not implemented")])
            }
        )
    }

    // MARK: events_search

    private static func eventsSearch(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "events_search",
            description: "Full-text search over captured events within a time window.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string")]),
                    "from": .object(["type": .string("string"), "format": .string("date-time")]),
                    "to": .object(["type": .string("string"), "format": .string("date-time")]),
                    "limit": .object(["type": .string("integer")]),
                ]),
                "required": .array([.string("query")]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { args in
                // The IPC events endpoint is a time-range scan; upstream query execution
                // is assumed to be handled by the daemon or by a future extension.
                let from = JSONBridge.parseDate(args["from"]) ?? Date(timeIntervalSince1970: 0)
                let to = JSONBridge.parseDate(args["to"]) ?? Date(timeIntervalSinceNow: 0)
                let limit = args["limit"]?.intValue
                let req = EventsRequest(from: from, to: to, source: nil, limit: limit)
                let resp = try await client.events(req)
                return try JSONBridge.encode(resp)
            }
        )
    }

    // MARK: app_usage (not implemented)

    private static func appUsage(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "app_usage",
            description: "Aggregate durations grouped by app or bundle over a period.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "period": .object(["type": .string("string")]),
                    "group_by": .object(["type": .string("string")]),
                ]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { _ in
                .object(["message": .string("not implemented")])
            }
        )
    }

    // MARK: list_rules

    private static func listRules(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "list_rules",
            description: "List all rules, optionally filtered to enabled-only.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "enabled_only": .object(["type": .string("boolean")]),
                ]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { args in
                let resp = try await client.rules()
                let enabledOnly = args["enabled_only"]?.boolValue ?? false
                let rules: [Rule]
                if enabledOnly {
                    rules = resp.rules.filter { $0.mode != .disabled }
                } else {
                    rules = resp.rules
                }
                return try JSONBridge.encode(RulesResponse(rules: rules))
            }
        )
    }

    // MARK: rule_explain (not implemented)

    private static func ruleExplain(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "rule_explain",
            description: "Explain a rule: NL, compiled DSL, recent firings, dry-run stats.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "rule_id": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("rule_id")]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { _ in
                .object(["message": .string("not implemented")])
            }
        )
    }

    // MARK: list_processes

    /// Hard cap mirrored from `ProcessesQueryApplier.maxLimit`. Enforced client-side so an
    /// over-sized `limit` never travels through XPC; the daemon enforces the same cap.
    static let listProcessesMaxLimit = 500

    private static func listProcesses(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "list_processes",
            description: "List live macOS processes with memory/CPU and an app category. Supports sort, limit, filter-by-category, and a minimum-memory filter. Read-only.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "sort_by": .object([
                        "type": .string("string"),
                        "enum": .array([.string("memory"), .string("cpu"), .string("name")]),
                    ]),
                    "order": .object([
                        "type": .string("string"),
                        "enum": .array([.string("asc"), .string("desc")]),
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(listProcessesMaxLimit),
                    ]),
                    "category": .object(["type": .string("string")]),
                    "include_restricted": .object(["type": .string("boolean")]),
                    "min_memory_bytes": .object([
                        "type": .string("integer"),
                        "minimum": .int(0),
                    ]),
                ]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { args in
                let query = ProcessesQuery(
                    sortBy: parseSortBy(args["sort_by"]),
                    order: parseOrder(args["order"]),
                    limit: clampLimit(args["limit"]?.intValue),
                    category: args["category"]?.stringValue,
                    includeRestricted: args["include_restricted"]?.boolValue ?? true,
                    minMemoryBytes: args["min_memory_bytes"]?.intValue.map(UInt64.init)
                )
                let page = try await client.listProcesses(query)
                return try JSONBridge.encode(page)
            }
        )
    }

    private static func parseSortBy(_ value: JSONValue?) -> ProcessesQuery.SortBy {
        guard let s = value?.stringValue, let sort = ProcessesQuery.SortBy(rawValue: s) else {
            return .memory
        }
        return sort
    }

    private static func parseOrder(_ value: JSONValue?) -> ProcessesQuery.Order {
        guard let s = value?.stringValue, let order = ProcessesQuery.Order(rawValue: s) else {
            return .desc
        }
        return order
    }

    private static func clampLimit(_ value: Int?) -> Int {
        guard let v = value else { return 50 }
        return max(1, min(v, listProcessesMaxLimit))
    }

    // MARK: recent_projects

    /// Default lookback when the caller omits `window` — one week balances
    /// "what did I do this week" recall against scan cost.
    private static let defaultWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Cap on events scanned for project-aware aggregation. Window-title parsing
    /// is cheap, but unbounded scans defeat the purpose of a fast assistant tool.
    private static let projectEventScanLimit = 5_000

    private static func recentProjects(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "recent_projects",
            description: "Group recent activity by repo (parsed from IDE window titles) with hours and last-seen timestamp.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "window": .object([
                        "type": .string("string"),
                        "description": .string("Lookback window like '24h', '7d', '90m'. Defaults to '7d'."),
                    ]),
                    "limit": .object(["type": .string("integer"), "minimum": .int(1)]),
                ]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { args in
                let now = Date()
                let window = parseWindow(args["window"]) ?? defaultWindow
                let limit = args["limit"]?.intValue
                let events = try await client.events(EventsRequest(
                    from: now.addingTimeInterval(-window),
                    to: now,
                    source: nil,
                    limit: projectEventScanLimit
                )).events

                let repos = aggregateRepoSpans(events: events, now: now)
                    .sorted { lhs, rhs in
                        lhs.totalSeconds == rhs.totalSeconds
                            ? lhs.name < rhs.name
                            : lhs.totalSeconds > rhs.totalSeconds
                    }
                let trimmed = limit.map { Array(repos.prefix(max(1, $0))) } ?? repos

                let projects: [JSONValue] = trimmed.map { repo in
                    .object([
                        "repo": .string(repo.name),
                        "total_seconds": .int(Int(repo.totalSeconds)),
                        "hours": .double((repo.totalSeconds / 3600 * 100).rounded() / 100),
                        "last_seen": .string(ISO8601.string(repo.lastSeen)),
                        "file_count": .int(repo.files.count),
                        "apps": .array(Array(repo.apps).sorted().map { .string($0) }),
                    ])
                }
                return .object([
                    "window_seconds": .int(Int(window)),
                    "projects": .array(projects),
                ])
            }
        )
    }

    // MARK: time_per_repo

    private static func timePerRepo(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "time_per_repo",
            description: "Hours spent per repo over a lookback window, ranked desc.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "window": .object([
                        "type": .string("string"),
                        "description": .string("Lookback window like '24h', '7d'. Defaults to '7d'."),
                    ]),
                ]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { args in
                let now = Date()
                let window = parseWindow(args["window"]) ?? defaultWindow
                let events = try await client.events(EventsRequest(
                    from: now.addingTimeInterval(-window),
                    to: now,
                    source: nil,
                    limit: projectEventScanLimit
                )).events

                let repos = aggregateRepoSpans(events: events, now: now)
                    .sorted { lhs, rhs in
                        lhs.totalSeconds == rhs.totalSeconds
                            ? lhs.name < rhs.name
                            : lhs.totalSeconds > rhs.totalSeconds
                    }
                let entries: [JSONValue] = repos.map { repo in
                    .object([
                        "repo": .string(repo.name),
                        "seconds": .int(Int(repo.totalSeconds)),
                        "hours": .double((repo.totalSeconds / 3600 * 100).rounded() / 100),
                    ])
                }
                return .object([
                    "window_seconds": .int(Int(window)),
                    "repos": .array(entries),
                ])
            }
        )
    }

    // MARK: files_touched

    private static func filesTouched(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "files_touched",
            description: "Distinct files seen in IDE window titles for a given repo over a window.",
            inputSchema: .object([
                "type": .string("object"),
                "required": .array([.string("repo")]),
                "properties": .object([
                    "repo": .object(["type": .string("string")]),
                    "window": .object([
                        "type": .string("string"),
                        "description": .string("Lookback window like '24h', '7d'. Defaults to '7d'."),
                    ]),
                    "limit": .object(["type": .string("integer"), "minimum": .int(1)]),
                ]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { args in
                guard let repoArg = args["repo"]?.stringValue, !repoArg.isEmpty else {
                    throw JSONRPCError.invalidParams
                }
                let now = Date()
                let window = parseWindow(args["window"]) ?? defaultWindow
                let limit = args["limit"]?.intValue
                let events = try await client.events(EventsRequest(
                    from: now.addingTimeInterval(-window),
                    to: now,
                    source: nil,
                    limit: projectEventScanLimit
                )).events

                let repos = aggregateRepoSpans(events: events, now: now)
                guard let match = repos.first(where: { $0.name.caseInsensitiveCompare(repoArg) == .orderedSame }) else {
                    return .object([
                        "repo": .string(repoArg),
                        "files": .array([]),
                    ])
                }
                let files = match.fileLastSeen
                    .sorted { $0.value > $1.value }
                    .map { (path: $0.key, lastSeen: $0.value) }
                let trimmed = limit.map { Array(files.prefix(max(1, $0))) } ?? files

                let fileEntries: [JSONValue] = trimmed.map { entry in
                    .object([
                        "path": .string(entry.path),
                        "last_seen": .string(ISO8601.string(entry.lastSeen)),
                    ])
                }
                return .object([
                    "repo": .string(match.name),
                    "files": .array(fileEntries),
                ])
            }
        )
    }

    // MARK: current_context

    private static func currentContext(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "current_context",
            description: "Best-effort right-now context — frontmost app, repo, file, branch (parsed from window title).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ]),
            enabled: true,
            isWrite: false,
            handler: { _ in
                let now = Date()
                // Look back 5 minutes for the latest frontmost-with-title event;
                // if the user hasn't switched apps recently the event is still fresh.
                let lookback: TimeInterval = 5 * 60
                let events = try await client.events(EventsRequest(
                    from: now.addingTimeInterval(-lookback),
                    to: now,
                    source: .frontmost,
                    limit: 200
                )).events

                let latest = events
                    .sorted { $0.timestamp > $1.timestamp }
                    .first { $0.attributes["windowTitle"] != nil }

                var app: String?
                if case let .app(_, name) = latest?.subject { app = name }

                let parsed: WindowTitleParser.Parsed? = {
                    guard let event = latest,
                          case let .app(bundleID, _) = event.subject,
                          let title = event.attributes["windowTitle"] else { return nil }
                    return WindowTitleParser.parse(title: title, bundleID: bundleID)
                }()

                return .object([
                    "app": parsed?.repo == nil && app == nil ? .null : .string(app ?? ""),
                    "repo": parsed?.repo.map { .string($0) } ?? .null,
                    "file": parsed?.file.map { .string($0) } ?? .null,
                    "branch": parsed?.branch.map { .string($0) } ?? .null,
                    "as_of": .string(ISO8601.string(latest?.timestamp ?? now)),
                ])
            }
        )
    }

    // MARK: - Aggregation helpers

    /// Maximum span we credit to a single window-title sample. Capture is
    /// roughly per-frontmost-change, but if the user steps away we don't want
    /// one stale sample to claim hours.
    private static let maxSpanPerSample: TimeInterval = 5 * 60

    struct RepoSpan {
        var name: String
        var totalSeconds: TimeInterval
        var lastSeen: Date
        var files: Set<String>
        var fileLastSeen: [String: Date]
        var apps: Set<String>
    }

    /// Walk events forward, parse IDE window titles, and credit time to the
    /// inferred repo. Time between samples is capped at `maxSpanPerSample` to
    /// avoid charging multi-hour idle gaps to whichever repo was last seen.
    static func aggregateRepoSpans(events: [ActivityEvent], now: Date) -> [RepoSpan] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var current: (repo: String, file: String?, app: String, since: Date)?
        var spans: [String: RepoSpan] = [:]

        func close(at end: Date) {
            guard let c = current else { return }
            let span = min(end.timeIntervalSince(c.since), maxSpanPerSample)
            guard span > 0 else { return }
            var bucket = spans[c.repo] ?? RepoSpan(
                name: c.repo,
                totalSeconds: 0,
                lastSeen: c.since,
                files: [],
                fileLastSeen: [:],
                apps: []
            )
            bucket.totalSeconds += span
            bucket.lastSeen = max(bucket.lastSeen, end)
            bucket.apps.insert(c.app)
            if let f = c.file {
                bucket.files.insert(f)
                if let prev = bucket.fileLastSeen[f] {
                    bucket.fileLastSeen[f] = max(prev, end)
                } else {
                    bucket.fileLastSeen[f] = end
                }
            }
            spans[c.repo] = bucket
        }

        for event in sorted {
            guard case let .app(bundleID, appName) = event.subject,
                  let title = event.attributes["windowTitle"],
                  let parsed = WindowTitleParser.parse(title: title, bundleID: bundleID),
                  let repo = parsed.repo else {
                close(at: event.timestamp)
                current = nil
                continue
            }
            close(at: event.timestamp)
            current = (repo: repo, file: parsed.file, app: appName, since: event.timestamp)
        }
        close(at: now)

        return Array(spans.values)
    }

    /// Parse a duration string. Accepts `<n>s`, `<n>m`, `<n>h`, `<n>d`, or a
    /// raw integer treated as seconds. Returns `nil` for unparseable input
    /// (callers fall back to a default).
    static func parseWindow(_ value: JSONValue?) -> TimeInterval? {
        guard let raw = value?.stringValue?.trimmingCharacters(in: .whitespaces).lowercased(),
              !raw.isEmpty else {
            if let n = value?.intValue, n > 0 { return TimeInterval(n) }
            return nil
        }
        let suffix = raw.last!
        let scale: TimeInterval
        let number: String
        switch suffix {
        case "s": scale = 1; number = String(raw.dropLast())
        case "m": scale = 60; number = String(raw.dropLast())
        case "h": scale = 3_600; number = String(raw.dropLast())
        case "d": scale = 86_400; number = String(raw.dropLast())
        default:
            if let n = Double(raw), n > 0 { return n }
            return nil
        }
        guard let n = Double(number), n > 0 else { return nil }
        return n * scale
    }
}

private enum ISO8601 {
    static func string(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
