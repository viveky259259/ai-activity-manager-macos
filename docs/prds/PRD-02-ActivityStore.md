# PRD-02 — ActivityStore (GRDB adapter)

**Status:** proposed · **Depends on:** PRD-01 · **Blocks:** PRD-06, PRD-09

## 1. Purpose

Persist activity events, sessions, and rules to SQLite via GRDB. Implement the `ActivityStore` port from ActivityCore. Provide fast range + full-text search.

## 2. Dependencies

- [GRDB.swift](https://github.com/groue/GRDB.swift) — actively maintained, FTS5 supported, first-class `Sendable`.
- Version pin: `6.29.0` or later (check at scaffold time).

## 3. Schema

### 3.1 `events`

| column | type | notes |
|---|---|---|
| id | TEXT (UUID) | PK |
| timestamp | REAL (seconds since reference date) | indexed |
| source | TEXT | indexed |
| subject_kind | TEXT | indexed |
| subject_primary | TEXT | e.g. bundleID, host, mode name; indexed |
| subject_secondary | TEXT | e.g. app name, URL path |
| attributes_json | TEXT | JSON blob |

Indexes:
- `idx_events_ts` on `(timestamp)`
- `idx_events_source_ts` on `(source, timestamp)`
- `idx_events_subject_primary_ts` on `(subject_primary, timestamp)`

### 3.2 `events_fts` (FTS5 virtual table)

Content-mirrored, auto-synced via triggers:
- columns: `subject_primary`, `subject_secondary`, `attributes_text` (extracted plain-text from JSON)
- tokenizer: `porter unicode61 remove_diacritics 2`

### 3.3 `rules`

| column | type |
|---|---|
| id | TEXT PK |
| name | TEXT |
| nl_source | TEXT |
| mode | TEXT |
| confirm_policy | TEXT |
| cooldown_seconds | REAL |
| trigger_json | TEXT |
| condition_json | TEXT NULL |
| actions_json | TEXT |
| created_at | REAL |
| updated_at | REAL |

### 3.4 `rule_firings`

| column | type |
|---|---|
| id | INTEGER PK AUTOINCREMENT |
| rule_id | TEXT FK → rules.id |
| fired_at | REAL |
| target | TEXT |
| outcome | TEXT |

## 4. Migrations

Use GRDB `DatabaseMigrator`. Migration strategy:

- Migrations are additive and forward-only.
- Each migration is a named Swift function with a stable identifier (`v1_initial`, `v2_add_ocr_text`).
- Tests lock the migrator against a golden schema dump.

## 5. API conformance

Implements every method on `ActivityStore`:

- `append` → batch `INSERT OR REPLACE` in a single transaction.
- `events(in:)` → `SELECT ... WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp, id LIMIT ?`.
- `search(_ query:)` → compiled to SQL + FTS5 MATCH when `fullText` present.
- `sessions(in:gapThreshold:)` → materialized on the fly from events; future optimization: materialized view.
- `rules`, `upsertRule`, `deleteRule` → straightforward.

## 6. Performance targets

| Op | Target @ 1M events |
|---|---|
| `append` of 50 events | ≤ 5 ms |
| `events(in:)` 1-day range | ≤ 20 ms |
| `search` FTS match | ≤ 50 ms |
| `sessions` 1-day range | ≤ 30 ms |

Measured via `XCTestCase.measure` with `maximumAverageMetric` set to 1.2× target.

## 7. Concurrency

- Single `DatabasePool` per store, shared across reads/writes.
- WAL mode enabled at init.
- Public API is `actor`-like via an internal serial dispatch queue; methods are `async` and safe from any task.

## 8. Acceptance

- [ ] In-memory SQLite (`:memory:`) used for tests.
- [ ] Migration from empty DB → current schema idempotent.
- [ ] FTS5 search returns expected rows for sample corpus.
- [ ] Property test: round-trip `ActivityEvent → append → events(in:) → equals` for 1k random events.
- [ ] Perf test meets targets on dev machine.

## 9. File locations

Default DB path: `~/Library/Application Support/com.yourco.ActivityManager/store.db`.

Resolution via `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`.

## 10. Out of scope

- Cloud sync (future).
- Vector search (future; PRD addendum).
- Retention/compaction (v1.1).
