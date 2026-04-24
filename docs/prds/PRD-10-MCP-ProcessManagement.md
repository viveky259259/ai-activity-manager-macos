# PRD-10 — MCP Process Management

**Status:** proposed · **Depends on:** PRD-04, PRD-06, PRD-08 · **Blocks:** none

## 1. Purpose

Expose live system-process data through MCP and extend the existing
`kill_app` write tool so AI agents can identify and terminate processes by
PID (not just bundle ID), optionally filtered by a coarse app category.

The motivating workflow: an agent asks *"what are the highest-memory
entertainment apps I'm not using right now?"*, receives a sorted list,
decides what to close, and issues targeted `kill_app` calls.

## 2. Motivation

Today's MCP surface only exposes *activity sessions* (collapsed windows of
focus). External agents cannot:

- See what's consuming CPU or memory **right now** (not what was focused).
- Target system / daemon processes that have no bundle ID.
- Reason about apps by category ("close entertainment apps during work hours").

## 3. Scope

- New read tool: `list_processes`.
- Extend `kill_app` write tool to accept `pid` in addition to `bundle_id`.
- Add static app-category lookup (bundled JSON, ~40 entries).
- Audit-event emission for both tools.
- Rate-limit integration (no new buckets).

## 4. Non-goals

- Dynamic / ML-based categorization.
- User-authored custom categories (revisit in v2).
- Server-side "pick the best apps to kill" heuristics — that reasoning stays
  with the calling agent.
- Process-tree or parent-child batch operations.
- Killing processes owned by other macOS users.

## 5. Tools

### 5.1 `list_processes` (read, always-on)

**Input**

| param | type | required | default | notes |
|---|---|---|---|---|
| `sort_by` | enum: `memory` / `cpu` / `name` | no | `memory` | |
| `order` | enum: `asc` / `desc` | no | `desc` | |
| `limit` | int | no | `50` | capped at 500 |
| `category` | string enum (see §6) | no | — | filter |
| `include_restricted` | bool | no | `true` | system processes with partial metrics |
| `min_memory_bytes` | uint64 | no | — | post-filter |

**Output**

```json
{
  "processes": [
    {
      "pid": 420,
      "bundle_id": "com.google.Chrome",
      "name": "Google Chrome",
      "user": "vivek",
      "memory_bytes": 823492608,
      "cpu_percent": 4.1,
      "threads": 32,
      "is_frontmost": false,
      "is_restricted": false,
      "category": "browser"
    }
  ],
  "system_memory_used_bytes": 12884901888,
  "system_memory_total_bytes": 34359738368,
  "sampled_at": "2026-04-24T14:50:11Z",
  "schema_version": 1
}
```

### 5.2 `kill_app` (extended)

Current signature kept; `pid` added as an alternative target.

| field | type | notes |
|---|---|---|
| `bundle_id` | string | exactly one of `bundle_id` / `pid` required |
| `pid` | int32 | if given, takes precedence |
| `strategy` | enum | unchanged |
| `force` | bool | unchanged |

**Resolution rules**

- `pid` + matching `NSRunningApplication` → resolve to bundle, use existing
  polite → force escalation ladder.
- `pid` without matching `NSRunningApplication` (daemons, launchd children):
  strategy is coerced to `.signal`; `force=false` sends `SIGTERM`,
  `force=true` sends `SIGKILL`. Polite-quit is not available for non-AppKit
  processes.
- `bundle_id` behaviour is unchanged.

**Safety rails** (all preserved from PRD-04 §3.4)

- `actionsEnabled` global kill switch.
- Per-target cooldown — keyed on `pid` for the pid-path, `bundleID` otherwise.
- SIP check: pid < 100 and `com.apple.*` LaunchDaemon paths refused.
- Unsaved-changes gate applies only when a bundle was resolved (AX API requires
  a running app reference).

## 6. App category catalog

Static resource: `Packages/ActivityMCP/Resources/app-categories.json`.

```json
{
  "version": 1,
  "categories": [
    "productivity", "communication", "browser",
    "entertainment", "development", "system", "utility"
  ],
  "map": {
    "com.apple.Safari": "browser",
    "com.google.Chrome": "browser",
    "com.microsoft.VSCode": "development",
    "com.tinyspeck.slackmacgap": "communication"
  }
}
```

~40 entries covering the common macOS app set. Unmapped bundles → `category`
field omitted. Extending the catalog is a data-only change (no rebuild of
consumers required once the resource is shipped).

## 7. Data plumbing

```
MCP client
  │  JSON-RPC tools/call list_processes
  ▼
activity-mcp (stdio)
  │  ActivityClientProtocol.listProcesses(...)
  ▼
IPCServer  (menu-bar app)
  │  calls LiveSystemProcessSampler.capture()
  │  attaches category from AppCategoryCatalog
  ▼
[ProcessSnapshot] → MCP response
```

- `LiveSystemProcessSampler` is reused — same source the Processes window uses,
  so MCP and UI stay consistent.
- `ActivityClientProtocol` grows one method: `listProcesses(_:ProcessesQuery)
  async throws -> ProcessesPage`.
- New domain type `ProcessSnapshot` lives in ActivityCore (not Core/App-only)
  so IPC can carry it.

## 8. Audit & rate limiting

- Every MCP call (read or write) emits `ActivityEvent(source: .mcp)` with
  `kind: "mcp_call"`, `identifier: <tool_name>`, attributes capturing
  non-sensitive filter args and outcome.
- `list_processes` counts against the **60 reads / min** bucket.
- `kill_app(pid)` counts against the **10 writes / min** bucket (no change).

## 9. Testing

- **Unit** — `AppCategoryCatalog`: load, lookup hit, lookup miss, version field.
- **Unit** — `ListProcessesTool`: arg parsing, category filter, sort stability,
  limit cap (500), restricted filter.
- **Unit** — `KillAppTool`: pid-only, bundle-only, both-given (reject),
  neither-given (reject), pid without NSRunningApplication → coerced to
  `.signal`.
- **Unit** — `ProcessTerminator.killApp(pid:)`: cooldown per pid, SIP refusal
  for pid < 100.
- **Integration** — IPC round-trip: MCP → XPC → sampler → MCP, sample size
  matches what the UI shows.
- **MCP protocol** — `tools/list` advertises `list_processes`; `tools/call`
  with invalid pid returns structured error envelope (no crash).
- **Rate-limit** — 61st read in a minute returns `-32000` / `Rate-limited`.

## 10. Acceptance

- [ ] `list_processes` with default params returns ≥ the count the Processes
      window shows, sorted by memory desc.
- [ ] `list_processes(category="browser")` returns only bundles mapped to
      `browser` in the catalog.
- [ ] `kill_app(pid=N)` where `N` is a user-owned daemon succeeds with
      strategy auto-coerced to `.signal`; same call with `actionsEnabled=false`
      returns `refused`.
- [ ] `kill_app(pid=N, bundle_id="x")` rejects with a validation error
      (exactly-one-of).
- [ ] Audit `ActivityEvent` emitted for every call, reads and writes alike.
- [ ] All existing tests still pass; new tests cover §9.

## 11. Out of scope

- Killing processes owned by other users.
- Dynamic or learned categorization.
- Process trees / parent-child batch operations.
- Exposing threads, open files, sockets, or memory maps.
