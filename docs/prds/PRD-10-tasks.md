# PRD-10 — Tasks

Ordered implementation plan for PRD-10 (MCP Process Management). Each task
is scoped to be small enough to land in a single commit. TDD: every task
that produces shippable behaviour leads with a failing test.

Conventions used below:
- **RED** = write failing tests first
- **GREEN** = implement minimum code to pass
- **REFACTOR** where called out

---

## Phase 1 — Category catalog (foundation, no IPC yet)

**T01** · Add resource file `Packages/ActivityMCP/Resources/app-categories.json`
with ~40 bundle-ID → category entries covering browsers, communication,
productivity, entertainment, development, system, utility.

**T02** · Wire the resource into `Package.swift`:
`.process("Resources")` on the `ActivityMCP` target. Verify `swift build`
picks it up.

**T03** · **RED** — `AppCategoryCatalogTests`:
- loads successfully from bundle
- returns expected category for 3 known BIDs
- returns `nil` for unknown BID
- `version` field surfaces (non-zero)

**T04** · **GREEN** — implement `AppCategoryCatalog` (static, lazy-loaded
singleton, Sendable, decodes JSON once, O(1) lookup).

---

## Phase 2 — ProcessSnapshot + IPC listing

**T05** · Add `ProcessSnapshot` to `Packages/ActivityCore/Sources/Domain/`:
pid, bundleID?, name, user, memoryBytes, cpuPercent, threads, isFrontmost,
isRestricted. `Sendable`, `Codable`, `Equatable`.

**T06** · Add `ProcessesQuery` + `ProcessesPage` request/response types in
ActivityCore. `ProcessesQuery { sortBy, order, limit, category?,
includeRestricted, minMemoryBytes? }`; `ProcessesPage { processes,
systemMemoryUsed, systemMemoryTotal, sampledAt }`.

**T07** · **RED** — extend `FakeActivityClient` with a `listProcesses` stub
and add test asserting arguments are forwarded unchanged.

**T08** · **GREEN** — extend `ActivityClientProtocol` with
`func listProcesses(_:ProcessesQuery) async throws -> ProcessesPage`.
Fake implementation returns a fixed list.

**T09** · **RED** — `IPCServerTests`: round-trip `listProcesses` over a
fake transport, assert payload equality.

**T10** · **GREEN** — implement `IPCServer.listProcesses` handler.
Construct snapshots by calling `LiveSystemProcessSampler.capture()` (inject
via existing dependency pattern), attach category via
`AppCategoryCatalog`, apply sort/filter/limit, include `SystemMemorySource`
values in the page.

**T11** · **REFACTOR** — extract sort/filter/limit from `IPCServer` into a
pure `ProcessesQueryApplier` so it can be unit-tested without XPC.
Move `IPCServerTests.listProcesses_sort` to `ProcessesQueryApplierTests`.

---

## Phase 3 — `list_processes` MCP tool

**T12** · Add JSON schema `Packages/ActivityMCP/Resources/schemas/list_processes.json`
mirroring PRD-10 §5.1.

**T13** · **RED** — `ListProcessesToolTests`:
- happy-path arg parsing (all fields)
- defaults applied when omitted
- `limit > 500` coerced to 500
- `category` passed through
- tool is read (not gated behind `enabled`)

**T14** · **GREEN** — implement `ListProcessesTool.make(client:)` in
`ReadTools.swift`. Register in `ToolRegistry`.

**T15** · **RED** — `MCPServerTests.tools_list_includesListProcesses` —
after init, `tools/list` advertises `list_processes` with its schema.

**T16** · **GREEN** — trivial if T14 registered correctly; otherwise fix.

---

## Phase 4 — `kill_app(pid)` extension

**T17** · **RED** — `KillAppRequestTests`:
- `bundle_id` only → valid
- `pid` only → valid
- both → validation error
- neither → validation error

**T18** · **GREEN** — relax `KillAppRequest` so `bundleID` is optional,
add `pid: Int32?`, add `validate()` enforcing exactly-one-of.

**T19** · **RED** — `ProcessTerminatorTests.killApp_byPid`:
- pid with matching `NSRunningApplication` → polite quit path, existing
  escalation
- pid with no match → `SIGTERM` (`force=false`) or `SIGKILL` (`force=true`)
- pid < 100 → refused (SIP)
- cooldown keyed on pid (second call within window refused)
- `actionsEnabled=false` → refused

**T20** · **GREEN** — implement pid resolution in `ProcessTerminator`:
look up NSRunningApplication by pid, if found delegate to existing
bundleID path; if not, coerce to signal and skip unsaved-changes AX check.

**T21** · **RED** — `KillAppToolTests`:
- `pid` param parsed through to request
- `bundle_id` + `pid` rejected at tool layer before IPC
- neither rejected
- tool still gated by `enabled` flag

**T22** · **GREEN** — update `WriteTools.swift::killApp` to accept pid,
perform the mutual-exclusion check, forward to IPC.

---

## Phase 5 — Audit events & rate limiting

**T23** · **RED** — `AuditEventTests` assert `list_processes` and
`kill_app(pid=..)` each emit one `ActivityEvent(source: .mcp,
kind: "mcp_call")` on success, with identifier matching the tool name and
attributes excluding the raw process list (too large).

**T24** · **GREEN** — thread audit emission through the MCP handler entry
point if not already covered. Avoid duplicating audits across tool + IPC
layers (pick one — the MCP handler is the right layer).

**T25** · **RED** — rate-limit test: 61 reads against `list_processes`
in a minute; 61st returns `-32000 Rate-limited`.

**T26** · **GREEN** — should pass because tool is read-bucket by default;
fix only if registry defaults are wrong.

---

## Phase 6 — End-to-end validation

**T27** · Manual smoke: build the app + `activity-mcp`, wire
`claude-desktop` via `amctl mcp install claude-desktop --print`, run a
`list_processes` and `kill_app(pid=..)` against a throwaway process. Verify
audit events appear in the app's timeline.

**T28** · Update `PRD-08-activity-mcp.md` tool-catalog table to include
`list_processes` and note the `pid` arg on `kill_app`.

**T29** · Update `README.md` if it enumerates MCP tool counts.

---

## Phase 7 — Ship

**T30** · Single commit per phase (or squash-merge the whole feature
branch), message prefixed `PRD-10:`. Push.

---

## Estimates (rough)

| Phase | Tasks | Effort |
|---|---|---|
| 1 — Category catalog | T01–T04 | ~1 h |
| 2 — ProcessSnapshot + IPC | T05–T11 | ~3 h |
| 3 — list_processes tool | T12–T16 | ~1.5 h |
| 4 — kill_app pid | T17–T22 | ~2 h |
| 5 — Audit + rate limit | T23–T26 | ~1 h |
| 6 — E2E | T27–T29 | ~1 h |
| **Total** | **30 tasks** | **~9.5 h** |

## Risks

- `LiveSystemProcessSampler.capture()` takes ~250 ms when it has to shell out
  to `top` for restricted processes. `list_processes` inherits that latency.
  Mitigation: cache the last snapshot for 2 s keyed on the query (matches UI
  refresh cadence).
- `ProcessTerminator` cooldowns currently key on `bundleID`. Adding a pid
  key can inadvertently allow a double-kill if the same process is targeted
  by both bundle and pid. Mitigation: when pid resolves to a bundle, store
  the cooldown under both keys.
- Static category catalog will drift as new apps ship. Low impact — data-only
  change, no schema churn.
