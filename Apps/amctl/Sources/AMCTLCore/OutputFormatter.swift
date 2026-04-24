import Foundation
import ArgumentParser
import ActivityCore
import ActivityIPC

/// Output format selectable on the command-line.
public enum OutputFormat: String, Sendable, CaseIterable, ExpressibleByArgument {
    case human
    case json
    case ndjson
}

/// Stateless formatting helpers. All methods return the string that should be
/// written to stdout; callers add a trailing newline if desired.
public enum OutputFormatter {
    public static let schemaVersion = 1

    // MARK: - JSON helpers

    private static func jsonEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func jsonEncoderCompact() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String {
        do {
            let data = try jsonEncoder().encode(value)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "{\"error\":\"\(error)\"}"
        }
    }

    private static func encodeJSONCompact<T: Encodable>(_ value: T) -> String {
        do {
            let data = try jsonEncoderCompact().encode(value)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "{\"error\":\"\(error)\"}"
        }
    }

    // MARK: - StatusResponse

    public static func format(_ status: StatusResponse, as format: OutputFormat) -> String {
        switch format {
        case .json, .ndjson:
            let envelope = StatusJSON(
                schema_version: schemaVersion,
                sources: status.sources,
                captured_event_count: status.capturedEventCount,
                actions_enabled: status.actionsEnabled,
                permissions: status.permissions
            )
            return encodeJSON(envelope)
        case .human:
            var out = ""
            out += "Sources:          \(status.sources.joined(separator: ", "))\n"
            out += "Events Captured:  \(status.capturedEventCount)\n"
            out += "Actions Enabled:  \(status.actionsEnabled ? "yes" : "no")\n"
            out += "Permissions:\n"
            let keys = status.permissions.keys.sorted()
            let width = keys.map(\.count).max() ?? 0
            for k in keys {
                let padded = k.padding(toLength: width, withPad: " ", startingAt: 0)
                out += "  \(padded)  \(status.permissions[k] ?? "")\n"
            }
            return out
        }
    }

    // MARK: - TimelineResponse

    public static func format(_ timeline: TimelineResponse, as format: OutputFormat) -> String {
        switch format {
        case .json:
            let envelope = TimelineJSON(
                schema_version: schemaVersion,
                sessions: timeline.sessions.map(SessionJSON.init(session:))
            )
            return encodeJSON(envelope)
        case .ndjson:
            return timeline.sessions.map { encodeJSONCompact(SessionJSON(session: $0)) }.joined(separator: "\n")
        case .human:
            return renderSessionTable(timeline.sessions)
        }
    }

    // MARK: - EventsResponse

    public static func format(_ events: EventsResponse, as format: OutputFormat) -> String {
        switch format {
        case .json:
            let envelope = EventsJSON(
                schema_version: schemaVersion,
                events: events.events.map(EventJSON.init(event:))
            )
            return encodeJSON(envelope)
        case .ndjson:
            return events.events.map { encodeJSONCompact(EventJSON(event: $0)) }.joined(separator: "\n")
        case .human:
            return renderEventTable(events.events)
        }
    }

    // MARK: - RulesResponse

    public static func format(_ rules: RulesResponse, as format: OutputFormat) -> String {
        switch format {
        case .json:
            let envelope = RulesJSON(
                schema_version: schemaVersion,
                rules: rules.rules.map(RuleJSON.init(rule:))
            )
            return encodeJSON(envelope)
        case .ndjson:
            return rules.rules.map { encodeJSONCompact(RuleJSON(rule: $0)) }.joined(separator: "\n")
        case .human:
            return renderRulesTable(rules.rules)
        }
    }

    // MARK: - KillAppResponse

    public static func format(_ kill: KillAppResponse, as format: OutputFormat) -> String {
        switch format {
        case .json, .ndjson:
            let envelope = KillJSON(schema_version: schemaVersion, outcome: kill.outcome)
            return encodeJSON(envelope)
        case .human:
            return "Outcome: \(kill.outcome)"
        }
    }

    // MARK: - Helpers

    private static func renderSessionTable(_ sessions: [ActivitySession]) -> String {
        if sessions.isEmpty { return "No sessions.\n" }
        let df = ISO8601DateFormatter()
        let rows: [[String]] = sessions.map { s in
            [
                df.string(from: s.startedAt),
                df.string(from: s.endedAt),
                formatDuration(s.duration),
                s.subject.kindName,
                s.subject.primaryKey,
            ]
        }
        let header = ["START", "END", "DUR", "KIND", "KEY"]
        return renderTable(header: header, rows: rows)
    }

    private static func renderEventTable(_ events: [ActivityEvent]) -> String {
        if events.isEmpty { return "No events.\n" }
        let df = ISO8601DateFormatter()
        let rows: [[String]] = events.map { e in
            [
                df.string(from: e.timestamp),
                e.source.rawValue,
                e.subject.kindName,
                e.subject.primaryKey,
            ]
        }
        let header = ["TIMESTAMP", "SOURCE", "KIND", "KEY"]
        return renderTable(header: header, rows: rows)
    }

    private static func renderRulesTable(_ rules: [Rule]) -> String {
        if rules.isEmpty { return "No rules.\n" }
        let rows: [[String]] = rules.map { r in
            [
                r.id.uuidString,
                r.name,
                r.mode.rawValue,
                r.trigger.kind.rawValue,
            ]
        }
        let header = ["ID", "NAME", "MODE", "TRIGGER"]
        return renderTable(header: header, rows: rows)
    }

    private static func renderTable(header: [String], rows: [[String]]) -> String {
        var widths = header.map(\.count)
        for row in rows {
            for (i, cell) in row.enumerated() where i < widths.count {
                widths[i] = max(widths[i], cell.count)
            }
        }
        func line(_ cells: [String]) -> String {
            cells.enumerated().map { i, c in
                c.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }
        var out = line(header) + "\n"
        for row in rows { out += line(row) + "\n" }
        return out
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%dh%02dm%02ds", h, m, s) }
        if m > 0 { return String(format: "%dm%02ds", m, s) }
        return "\(s)s"
    }
}

// MARK: - JSON envelopes

private struct StatusJSON: Encodable {
    let schema_version: Int
    let sources: [String]
    let captured_event_count: Int
    let actions_enabled: Bool
    let permissions: [String: String]
}

private struct TimelineJSON: Encodable {
    let schema_version: Int
    let sessions: [SessionJSON]
}

private struct SessionJSON: Encodable {
    let id: String
    let subject_kind: String
    let subject_key: String
    let started_at: Date
    let ended_at: Date
    let duration_seconds: Double
    let sample_count: Int

    init(session: ActivitySession) {
        self.id = session.id.uuidString
        self.subject_kind = session.subject.kindName
        self.subject_key = session.subject.primaryKey
        self.started_at = session.startedAt
        self.ended_at = session.endedAt
        self.duration_seconds = session.duration
        self.sample_count = session.sampleCount
    }
}

private struct EventsJSON: Encodable {
    let schema_version: Int
    let events: [EventJSON]
}

private struct EventJSON: Encodable {
    let id: String
    let timestamp: Date
    let source: String
    let subject_kind: String
    let subject_key: String
    let attributes: [String: String]

    init(event: ActivityEvent) {
        self.id = event.id.uuidString
        self.timestamp = event.timestamp
        self.source = event.source.rawValue
        self.subject_kind = event.subject.kindName
        self.subject_key = event.subject.primaryKey
        self.attributes = event.attributes
    }
}

private struct RulesJSON: Encodable {
    let schema_version: Int
    let rules: [RuleJSON]
}

private struct RuleJSON: Encodable {
    let id: String
    let name: String
    let nl_source: String
    let mode: String
    let trigger_kind: String

    init(rule: Rule) {
        self.id = rule.id.uuidString
        self.name = rule.name
        self.nl_source = rule.nlSource
        self.mode = rule.mode.rawValue
        self.trigger_kind = rule.trigger.kind.rawValue
    }
}

private struct KillJSON: Encodable {
    let schema_version: Int
    let outcome: String
}
