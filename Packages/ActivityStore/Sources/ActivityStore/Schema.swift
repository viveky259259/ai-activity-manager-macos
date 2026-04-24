import Foundation
import GRDB

enum Schema {
    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "events") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("timestamp", .double).notNull().indexed()
                t.column("source", .text).notNull().indexed()
                t.column("subject_kind", .text).notNull().indexed()
                t.column("subject_primary", .text).notNull().indexed()
                t.column("subject_secondary", .text).notNull()
                t.column("subject_json", .text).notNull()
                t.column("attributes_json", .text).notNull()
            }
            try db.create(index: "idx_events_source_ts", on: "events", columns: ["source", "timestamp"])
            try db.create(index: "idx_events_subject_primary_ts", on: "events", columns: ["subject_primary", "timestamp"])

            try db.create(virtualTable: "events_fts", using: FTS5()) { t in
                t.tokenizer = .porter(wrapping: .unicode61())
                t.synchronize(withTable: "events")
                t.column("subject_primary")
                t.column("subject_secondary")
            }

            try db.create(table: "rules") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("name", .text).notNull()
                t.column("nl_source", .text).notNull()
                t.column("mode", .text).notNull()
                t.column("confirm_policy", .text).notNull()
                t.column("cooldown_seconds", .double).notNull()
                t.column("trigger_json", .text).notNull()
                t.column("condition_json", .text)
                t.column("actions_json", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
            }

            try db.create(table: "rule_firings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("rule_id", .text).notNull().references("rules", onDelete: .cascade)
                t.column("fired_at", .double).notNull().indexed()
                t.column("target", .text).notNull()
                t.column("outcome", .text).notNull()
            }
        }
    }
}
