# Concepts — the vocabulary you'll need

The product has a small vocabulary. Once you have it, the rest of the docs read faster.

---

## Event

The atomic unit of capture. Each event is one row in `events` (SQLite), with:

- `timestamp` (UTC, microsecond precision)
- `kind` — `frontmostChanged`, `idleEntered`, `idleEnded`, `focusModeChanged`, `windowTitleChanged`, etc.
- `bundle_id`, `app_name`, `window_title` (when applicable)
- `parsed_repo`, `parsed_file` — extracted from the window title by `WindowTitleParser` for known IDEs

Events are written as they happen. Capture is a tight loop sampling NSWorkspace's frontmost app + AX (Accessibility) for the window title.

**Privacy boundary:** events store *titles*, not contents. We never read file bodies, browser URLs (browsers don't expose those via AX without explicit user automation), or keystrokes.

---

## Session

A *session* is a virtual concept — a contiguous run of events without a meaningful gap. The Timeline tab and `query_timeline` collapse rapid app-switching into sessions so the UI is readable.

Default session boundaries:
- 5+ minutes idle → ends current session
- App switch *within* the same repo → same session
- App switch *to a different repo* → new session

Sessions are computed at query time; they aren't a separate table. So changing the heuristic doesn't require a migration.

---

## Repo and file (window-title parsing)

Many IDEs encode the current repo and file in the window title. `WindowTitleParser` (in `Packages/ActivityMCP`) recognizes:

| IDE | Title format |
|---|---|
| Cursor | `myfile.ts — myrepo` |
| VSCode | `myfile.ts - myrepo - Visual Studio Code` |
| Xcode | `myrepo — myfile.swift` |
| Zed | `myrepo — myfile.rs` |
| JetBrains (IntelliJ, PyCharm, etc.) | `myrepo - myfile.py [myproject]` |
| Terminal / iTerm | `~/Documents/myrepo` (path → repo) |

For unrecognized apps, `parsed_repo` and `parsed_file` are null — the event still records bundle ID, app name, and raw title. We can extend the parser with a PR; the test suite has fixtures for every supported title format.

---

## MCP server (`activity-mcp`)

A standalone binary speaking JSON-RPC over stdio per the [Model Context Protocol](https://modelcontextprotocol.io) spec. It's not a daemon — it's launched on-demand by the host (Claude Desktop, Cursor, Zed, your custom agent) and lives only as long as the conversation.

It reads from the **same SQLite database** the menu-bar app writes to. So you can run the menu-bar app for capture + the MCP server for the AI surface, and they coordinate through the file system.

If you don't run the menu-bar app, you can still install `activity-mcp` for the *read* tools, but the database will be empty (nothing's capturing). The full app is what makes the timeline useful.

---

## Read tool

A side-effect-free MCP tool. There are 12:

| Tool | Returns |
|---|---|
| `status` | Daemon health, capture-source enabled flags |
| `list_processes` | Live process list with CPU/memory |
| `timeline` | Recent events, paginated |
| `query_timeline` | FTS5 search over events |
| `permissions_status` | Live TCC permission state |
| `current_activity` | What's frontmost right now |
| `list_rules` | Configured rules |
| `audit_log` | Recent tool-call audit entries |
| `recent_projects` | Repos touched, ranked by recency |
| `time_per_repo` | Hours per repo over a window |
| `files_touched` | Distinct files seen in IDE titles |
| `current_context` | Repo + branch + file + app right now |

Read tools are rate-limited at **60/min per client**. The limit is a sliding window; the client identifier is whatever the host advertises in the MCP `initialize` handshake.

---

## Write tool

A tool with side effects. There are 4:

| Tool | What it does |
|---|---|
| `kill_app` | SIGTERM (then SIGKILL after grace) on a process by bundle ID |
| `create_rule` | Add a JSON rule to the rules engine |
| `update_rule` | Modify an existing rule |
| `delete_rule` | Remove a rule |

Write tools have **two gates** plus rate limiting:

1. **Actions toggle** in Settings (or `amctl actions enable`). Default off. The toggle's state is read on every call — flipping it disables in-flight tools immediately. The AI cannot flip the toggle (no tool is exposed for it).
2. **Per-tool guards.** `kill_app` enforces a 60s cooldown per bundle, refuses SIP-protected processes, and bails on apps with unsaved changes.
3. **Rate limit** — 10/min per client.

Every call lands in the audit log regardless of outcome (allowed, refused, errored).

---

## Actions toggle

The single bit that decides whether the AI can affect your machine. Off by default, off after every reinstall, off on every fresh install. There is no default-on flag and no flag to make it default-on.

Why a single toggle and not per-tool granularity? Because cognitive overhead is the enemy of safety. If users have to think about 4 toggles, they'll just enable them all. One toggle is "I trust this AI enough to let it touch things" — easier to reason about, easier to audit.

If you want finer-grained control, the rules engine lets you scope which rules are active without changing the toggle.

---

## Rate limiting

Per-client sliding window:

- **60/min reads**
- **10/min writes**

Sliding window means a burst of 60 calls in 5 seconds is allowed, but you can't sustain >1/sec average. The 11th write in a minute returns an error response (not a silent drop) so the AI can react.

Why this matters: under prompt injection (some other tool returning hostile content that tries to talk the AI into a kill-spree), the rate limit is a hard cap on blast radius. The audit log captures the attempt.

---

## Audit log

A separate SQLite table recording every `tools/call`:

- Timestamp
- Tool name
- Arguments (JSON)
- Result (JSON, truncated for huge payloads)
- Calling client (from MCP `initialize`)
- Outcome (`allowed`, `refused`, `errored`, `rate_limited`)

The log is append-only at the application level — no MCP tool deletes from it. The user can `rm` the SQLite file via the file system; that's intentional.

Inspect it via:
```bash
amctl audit log              # last 50
amctl audit log --since 1h   # last hour
amctl audit log --tool kill_app
```

Or call `audit_log` from the AI (read tool, no permissions needed).

---

## LLM provider

Two backends, ranked:

1. **Apple Foundation Models** (`AppleFoundationProvider`) — on-device, requires macOS 26 (Tahoe), zero network egress. Default if available.
2. **Anthropic** (`AnthropicProvider`) — cloud, requires user-pasted API key (kept in Keychain). Off until you save a key. Used for Insights summaries when on-device isn't an option.

If neither is available, the LLM-dependent features (Insights tab, NL→rule translation) show "no provider configured" rather than silently going to a cloud service.

The provider is **only used by the menu-bar app**. The MCP server never calls an LLM — it returns raw structured data and lets the calling AI host's model do the reasoning.

---

## Rule

A declarative trigger + condition + action(s) JSON file. Lives in `~/Library/Application Support/ActivityManager/rules/`.

Schema (informal):
```json
{
  "name": "Auto-focus when Slack closed",
  "trigger": {"type": "appQuit", "bundleId": "com.tinyspeck.slackmacgap"},
  "condition": {"during": "workHours"},
  "actions": [{"type": "setFocusMode", "mode": "Work"}],
  "confirmPolicy": "auto"
}
```

Triggers, conditions, actions, and confirm policies are documented in [`../examples/rules/README.md`](../examples/rules/README.md). The rules engine is the deterministic counterpart to the AI: rules react fast, predictably, and without an LLM in the loop.

---

## TCC permissions

macOS gates several APIs behind user-granted permissions. You need:

- **Accessibility** — required. Without it, no window titles. The Overview tab will look empty.
- **Calendar** — optional. For calendar correlation in `query_timeline`.
- **Focus** — required to read/write Focus modes. Optional if you don't use Focus-related rules.
- **Automation** — required for `kill_app` to terminate certain apps gracefully.

`permissions_status` is a read tool — the AI can tell you what's missing.

---

## What this is *not*

- Not a screen recorder. No pixels are captured.
- Not a keylogger. No keystrokes are captured.
- Not a clipboard recorder.
- Not a browser-history reader.
- Not a network sniffer.

The only thing we capture is what macOS willingly tells the foreground app: bundle ID, app name, window title, idle state, focus state. That's the entire surface.
