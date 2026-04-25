# MCP examples

`activity-mcp` is a stdio JSON-RPC server. Pipe a request in, get a JSON
response out. Useful for:

- Smoke-testing your install (`tools/list` should return ~12 entries)
- Wiring it up to Claude Desktop, Cursor, Zed, or any compliant MCP host
- Driving it from scripts when you don't want to spin up a host

## Quick smoke test

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | activity-mcp
```

You should see a JSON response listing the available read tools (and write
tools, if you enabled them with `--allow-writes`).

## Files

| File | What it asks | Try it |
|---|---|---|
| [`tools-list.json`](./tools-list.json) | List every tool the server exposes | `cat tools-list.json \| activity-mcp` |
| [`recent-projects.json`](./recent-projects.json) | "What projects have I worked on in the last 24h?" | `cat recent-projects.json \| activity-mcp` |
| [`time-per-repo.json`](./time-per-repo.json) | "How much time per repo over the last week?" | `cat time-per-repo.json \| activity-mcp` |
| [`current-context.json`](./current-context.json) | "What am I doing right now?" | `cat current-context.json \| activity-mcp` |
| [`claude-desktop-config.json`](./claude-desktop-config.json) | Drop-in `mcpServers` block for Claude Desktop's config | Merge into `~/Library/Application Support/Claude/claude_desktop_config.json` |
| [`zed-config.jsonc`](./zed-config.jsonc) | Zed `context_servers` block | Merge into your Zed `settings.json` |

## Read tools (v1.0)

- `recent_projects` — projects active in a window, ranked by recency.
- `time_per_repo` — hours per repo over a window, ranked desc.
- `time_on_projects` — alias of the above with extra metadata.
- `files_touched` — distinct files seen in IDE titles for a given repo.
- `current_activity` — the frontmost app + window title right now.
- `current_context` — recent activity rolled up into a 1–3 sentence summary.
- `query_timeline` — natural-language query over the local timeline.
- `events_search` — substring search over events.
- `timeline_range` — events between two timestamps.
- `list_rules` — currently-loaded rules.
- `audit_log` — recent MCP calls (rate-limit transparency).
- `app_categories` — the bundle-ID → category catalog.

## Write tools (require `--allow-writes` AND the GUI's Actions toggle)

- `enable_focus_mode`, `disable_focus_mode`
- `kill_app`, `launch_app`

Every write call lands in the local audit log with the calling client's ID,
timestamp, arguments, and outcome.
