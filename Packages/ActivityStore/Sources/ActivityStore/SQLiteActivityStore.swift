import Foundation
import GRDB
import ActivityCore

public final class SQLiteActivityStore: ActivityStore, Sendable {
    private let dbPool: DatabasePool

    public init(url: URL) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL")
        }
        self.dbPool = try DatabasePool(path: url.path, configuration: config)
        try migrate()
    }

    public static func temporary() throws -> SQLiteActivityStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("activity-store-\(UUID().uuidString).sqlite")
        return try SQLiteActivityStore(url: url)
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        Schema.register(&migrator)
        try migrator.migrate(dbPool)
    }

    public func append(_ events: [ActivityEvent]) async throws {
        guard !events.isEmpty else { return }
        try await dbPool.write { db in
            for event in events {
                let record = try EventRecord.from(event)
                try record.save(db)
            }
        }
    }

    public func events(in range: DateInterval, limit: Int?) async throws -> [ActivityEvent] {
        try await dbPool.read { db in
            let start = range.start.timeIntervalSince1970
            let end = range.end.timeIntervalSince1970
            var sql = "SELECT * FROM events WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp ASC, id ASC"
            var args: [DatabaseValueConvertible] = [start, end]
            if let limit {
                sql += " LIMIT ?"
                args.append(limit)
            }
            let records = try EventRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return try records.map { try $0.toEvent() }
        }
    }

    public func search(_ query: TimelineQuery) async throws -> [ActivityEvent] {
        try await dbPool.read { db in
            var sql = "SELECT events.* FROM events"
            var args: [DatabaseValueConvertible] = []
            var clauses: [String] = []

            if let ft = query.fullText, !ft.isEmpty {
                sql += " JOIN events_fts ON events_fts.rowid = events.rowid"
                clauses.append("events_fts MATCH ?")
                args.append(Self.ftsEscape(ft))
            }

            clauses.append("events.timestamp >= ?")
            args.append(query.range.start.timeIntervalSince1970)
            clauses.append("events.timestamp <= ?")
            args.append(query.range.end.timeIntervalSince1970)

            if let sources = query.sources, !sources.isEmpty {
                let placeholders = Array(repeating: "?", count: sources.count).joined(separator: ", ")
                clauses.append("events.source IN (\(placeholders))")
                for s in sources { args.append(s.rawValue) }
            }

            if let bundles = query.bundleIDs, !bundles.isEmpty {
                let placeholders = Array(repeating: "?", count: bundles.count).joined(separator: ", ")
                clauses.append("events.subject_kind = 'app' AND events.subject_primary IN (\(placeholders))")
                for b in bundles { args.append(b) }
            }

            if let host = query.hostContains {
                clauses.append("events.subject_kind = 'url' AND events.subject_primary LIKE ?")
                args.append("%\(host)%")
            }

            if !clauses.isEmpty {
                sql += " WHERE " + clauses.joined(separator: " AND ")
            }
            sql += " ORDER BY events.timestamp ASC, events.id ASC"
            if let limit = query.limit {
                sql += " LIMIT ?"
                args.append(limit)
            }

            let records = try EventRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return try records.map { try $0.toEvent() }
        }
    }

    public func sessions(in range: DateInterval, gapThreshold: TimeInterval) async throws -> [ActivitySession] {
        let events = try await events(in: range, limit: nil)
        return SessionCollapser().collapse(events, gapThreshold: gapThreshold)
    }

    public func rules() async throws -> [Rule] {
        try await dbPool.read { db in
            let records = try RuleRecord.fetchAll(db, sql: "SELECT * FROM rules ORDER BY created_at ASC")
            return try records.map { try $0.toRule() }
        }
    }

    public func upsertRule(_ rule: Rule) async throws {
        try await dbPool.write { db in
            try RuleRecord.from(rule).save(db)
        }
    }

    public func deleteRule(id: UUID) async throws {
        try await dbPool.write { db in
            _ = try RuleRecord.deleteOne(db, key: id.uuidString)
        }
    }

    private static func ftsEscape(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
