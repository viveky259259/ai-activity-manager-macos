# PRD-08 — activity-mcp (MCP server)

**Status:** proposed · **Depends on:** PRD-06 · **Blocks:** none

## 1. Purpose

MCP server exposing Activity Manager capabilities to MCP-capable hosts (Claude Desktop, Cursor, Zed, custom clients). Read tools on by default; write tools opt-in per tool.

## 2. Transport

- **stdio** (default) — for Claude Desktop and most hosts.
- **Streamable HTTP** (optional) — `127.0.0.1:PORT`, bearer-token authed, token in Keychain.

Both transports share the same handler core.

## 3. MCP compliance

- Implements Model Context Protocol as of 2025-11 spec.
- Advertises capabilities: `tools`, `resources` (timeline-as-resource experimental).
- Does not advertise `sampling` in v1.

## 4. Tool catalog

### 4.1 Read tools (always enabled)

| name | input schema | returns |
|---|---|---|
| `current_activity` | — | frontmost app, window, session duration, focus mode, idle |
| `timeline_range` | `from`, `to`, `app_filter?`, `limit?` | list of sessions |
| `timeline_query` | `question`, `time_hint?` | NL answer + cited session IDs |
| `events_search` | `query`, `time_range?`, `limit?` | events with FTS matches |
| `app_usage` | `period`, `group_by` | aggregate durations |
| `list_rules` | `enabled_only?` | rules incl. compiled DSL |
| `rule_explain` | `rule_id` | NL + DSL + firings + dry-run stats |
| `list_processes` | `sort_by?`, `order?`, `limit?`, `category?`, `include_restricted?`, `min_memory_bytes?` | process list w/ memory/CPU + app category + system memory snapshot (PRD-10) |

### 4.2 Write tools (disabled by default)

| name | input | safety |
|---|---|---|
| `propose_rule` | `nl_description` | always creates in dry-run; user must activate in-app |
| `set_rule_enabled` | `rule_id`, `enabled` | posts notification with 10 s undo window |
| `kill_app` | `bundle_id` **or** `pid`, `strategy?`, `force?` | runs same `ProcessTerminator` with all safety rails; exactly one of bundle_id/pid is required (PRD-10) |
| `set_focus_mode` | `mode_name`/null | standard |

## 5. Safety model

- Default config: reads on, writes off.
- Each MCP call creates an `ActivityEvent { source: .mcp, subject: .custom(kind: "mcp_call", identifier: toolName), attributes: [...] }` — fully auditable.
- Rate limits per client (keyed on the host's declared client ID):
  - 60 read / min
  - 10 write / min
- Redactor applied to outputs heading to cloud-hosted clients (configurable per-client).

## 6. Install UX

Implemented via `amctl mcp install <target>`:
- `claude-desktop` → edits `~/Library/Application Support/Claude/claude_desktop_config.json`.
- `cursor` → edits Cursor's MCP settings.
- `zed` → Zed's extension-based MCP integration.

Dry-run mode (`--print`) just outputs the JSON snippet.

## 7. Schemas

Per-tool JSONSchemas under `ActivityMCP/Resources/schemas/`.
All schemas have a `schema_version` output field.

## 8. Testing strategy

- Unit tests per tool handler using `FakeIPCClient`.
- MCP protocol-level tests via a minimal stdio harness that pipes JSON-RPC in and reads JSON-RPC out; asserts the server honors protocol handshake, tool listing, tool calls, error envelopes.
- Rate limiting tests.
- Audit event emission tests.

## 9. Acceptance

- [ ] `tools/list` returns all 8 read tools + 4 write tools (write tools marked `disabled` when gated).
- [ ] `tools/call` on a disabled write tool returns structured error, does not call IPC.
- [ ] Each tool emits an audit `ActivityEvent`.
- [ ] Rate limit test: 61 reads in 60s → 61st returns error.
- [ ] `amctl mcp install claude-desktop --print` outputs valid JSON that matches spec.

## 10. Out of scope

- MCP sampling capability.
- Remote (non-localhost) HTTP transport.
- Multi-user token management.
