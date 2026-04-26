# Reference — every tool and every command

Authoritative tool + CLI surface. For semantics, see [`concepts.md`](concepts.md). For the API typings (DocC-generated), see https://viveky259259.github.io/ai-activity-manager-macos/.

---

## MCP tools (16 total)

All tools speak JSON-RPC over stdio. Schemas are published via `tools/list` so any MCP-compliant host auto-discovers them. Verify with `./Scripts/mcp-inspect.sh`.

### Read tools (12) — rate-limited 60/min/client

#### `status`
**What:** Daemon health + capture-source toggles.
**Args:** none.
**Returns:** `{ running: bool, sources: {frontmost, idle, focus}, dbPath, eventCount }`
**When to use:** First-line diagnostic. "Is the thing capturing?"

#### `list_processes`
**What:** Live process list, like `ps` but with friendly names.
**Args:** `{ sortBy?: "memory" | "cpu" | "name", limit?: int }`
**Returns:** Array of `{ pid, bundleId, name, cpuPercent, memoryMB, isFrontmost }`
**Use:** "What's hogging RAM right now?"

#### `timeline`
**What:** Recent events, paginated.
**Args:** `{ limit?: int (default 100), before?: timestamp }`
**Returns:** Array of events.
**Use:** Pagination scan. Prefer `query_timeline` for search.

#### `query_timeline`
**What:** FTS5 full-text search over the timeline.
**Args:** `{ query: string, since?: timestamp, until?: timestamp, limit?: int }`
**Returns:** Matching events with snippet highlights.
**Use:** "Find when I was in the auth code last Tuesday."

#### `permissions_status`
**What:** Live TCC state.
**Args:** none.
**Returns:** `{ accessibility, calendar, focus, automation }` — each `granted | denied | notDetermined`.
**Use:** Diagnose capture gaps.

#### `current_activity`
**What:** Snapshot of frontmost app right now.
**Args:** none.
**Returns:** `{ bundleId, appName, windowTitle, parsedRepo?, parsedFile?, isIdle }`
**Use:** Lightweight "what am I doing" probe.

#### `list_rules`
**What:** All configured rules.
**Args:** `{ enabledOnly?: bool }`
**Returns:** Array of rule JSON.

#### `audit_log`
**What:** Recent tool-call audit entries.
**Args:** `{ since?: timestamp, tool?: string, limit?: int }`
**Returns:** Array of `{ timestamp, tool, args, result, client, outcome }`
**Use:** "What has the AI done lately?"

#### `recent_projects`
**What:** Repos touched, ranked by recency.
**Args:** `{ window?: "1h" | "24h" | "7d" | "30d" }` (default 7d)
**Returns:** `[{ repo, hours, lastSeen, fileCount }]`
**Use:** Standup, weekly review.

#### `time_per_repo`
**What:** Hours per repo, sortable. Like `recent_projects` but sorted by time, not recency.
**Args:** `{ window?: "1h" | "24h" | "7d" | "30d" }`
**Returns:** Same shape as `recent_projects`, sorted desc by hours, ties broken by name asc.
**Use:** "Where did my week go?"

#### `files_touched`
**What:** Distinct files seen in IDE titles.
**Args:** `{ repo?: string, window?: "1h" | "24h" | "7d" | "30d", limit?: int }`
**Returns:** `[{ file, repo, lastSeen, focusCount }]`
**Use:** PR description; "what files mattered this week?"

#### `current_context`
**What:** Best-effort context: repo, branch, file, app, focus mode right now.
**Args:** none.
**Returns:** `{ repo?, branch?, file?, app, focusMode?, idle }`
**Use:** First call in any "what am I doing / where was I" prompt.

### Write tools (4) — Actions toggle required, 10/min/client

#### `kill_app`
**What:** Gracefully terminate an app by bundle ID. SIGTERM, then SIGKILL after a grace period.
**Args:** `{ bundleId: string, force?: bool }`
**Returns:** `{ success, pid, terminatedAt, reason? }`
**Guards:**
- Actions toggle must be on
- Per-bundle 60s cooldown
- Refuses SIP-protected processes
- Refuses apps reporting unsaved changes via AX

#### `create_rule`
**What:** Add a new rule.
**Args:** `{ rule: RuleJSON }` — see [`../examples/rules/`](../examples/rules/) for schema.
**Returns:** `{ id, savedTo }`

#### `update_rule`
**What:** Modify an existing rule.
**Args:** `{ id: string, rule: RuleJSON }`
**Returns:** `{ id, updated }`

#### `delete_rule`
**What:** Delete a rule by ID.
**Args:** `{ id: string }`
**Returns:** `{ id, deleted }`

---

## `amctl` CLI

Standalone CLI mirroring the MCP read surface plus admin commands. Installed via `brew install amctl` or bundled with the full app.

### Diagnostic

| Command | Description |
|---|---|
| `amctl status` | Daemon snapshot + capture source state |
| `amctl permissions` | Live TCC status |
| `amctl version` | Build version + commit SHA |

### Read

| Command | Description |
|---|---|
| `amctl events` | Stream raw events (one-shot) |
| `amctl tail` | Stream events, follow mode (`tail -f` semantics) |
| `amctl query <text>` | FTS5 search |
| `amctl top` | Top apps by capture frequency |
| `amctl timeline` | Session-collapsed view |
| `amctl recent-projects` | Repos by recency |
| `amctl time-per-repo` | Hours per repo |
| `amctl files-touched [--repo R]` | Distinct files |
| `amctl current` | Current context |

### Admin

| Command | Description |
|---|---|
| `amctl actions enable` | Turn the destructive-action gate on |
| `amctl actions disable` | Turn it off |
| `amctl actions status` | Read current state |
| `amctl audit log [--since 1h] [--tool kill_app]` | Inspect audit entries |
| `amctl rules list` | Show all rules |
| `amctl rules show <id>` | Show one rule |

### MCP host integration

| Command | Description |
|---|---|
| `amctl mcp install claude-desktop` | Merge config into Claude Desktop's JSON |
| `amctl mcp install cursor` | Same, for Cursor |
| `amctl mcp install zed` | Same, for Zed |
| `amctl mcp config --host <name>` | Print the config snippet (don't write) |
| `amctl mcp doctor` | Verify wiring end-to-end |
| `amctl mcp token rotate` | Rotate the local MCP server token |

### Output formats

Most commands accept `--format json` for machine-readable output. The shell script examples in `examples/amctl/` use `jq` to parse this.

---

## Configuration files

| Path | What |
|---|---|
| `~/Library/Application Support/ActivityManager/activity.sqlite` | Main database (events, sessions, rules, audit log) |
| `~/Library/Application Support/ActivityManager/settings.plist` | Toggles, retention, provider choice |
| `~/Library/Logs/ActivityManager/*.log` | Daemon logs |
| Keychain: `service=com.viveky.ActivityManager, account=anthropic-api-key` | Anthropic key, if you saved one |

Removing the database is the canonical "reset to factory" operation. The schema is rebuilt on next launch.

---

## Environment variables

| Variable | What | Default |
|---|---|---|
| `ACTIVITY_MANAGER_DB_PATH` | Override database location | `~/Library/Application Support/ActivityManager/activity.sqlite` |
| `ACTIVITY_MANAGER_LOG_LEVEL` | `debug | info | warn | error` | `info` |
| `RUN_SNAPSHOT_TESTS` | Set to `1` to run image-snapshot tests (CI gates them off by default) | unset |

---

## Exit codes (`amctl`, `activity-mcp`)

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Generic error |
| 2 | Bad arguments |
| 3 | Permission denied (TCC or filesystem) |
| 4 | Daemon unreachable |
| 5 | Database locked or corrupt |
| 64 | Misuse (no command given, etc.) |

---

## File-format references

- **Rules JSON** — [`../examples/rules/README.md`](../examples/rules/README.md)
- **MCP tool fixtures** — [`../examples/mcp/`](../examples/mcp/) (real captures of `tools/list` and tool responses)
- **DocC API reference** — https://viveky259259.github.io/ai-activity-manager-macos/

---

## See also

- [`getting-started.md`](getting-started.md) — install + first wiring
- [`use-cases.md`](use-cases.md) — copy-paste prompts that work today
- [`concepts.md`](concepts.md) — vocabulary
- [`privacy-and-safety.md`](privacy-and-safety.md) — the safety story
- [`features.md`](features.md) — current release inventory
