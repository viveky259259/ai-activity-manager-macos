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
}
