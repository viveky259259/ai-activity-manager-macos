# @viveky/activity-mcp

[![MIT](https://img.shields.io/badge/license-MIT-green.svg)](../LICENSE)

Stdio MCP server that gives your AI assistant memory of what you actually
worked on. Works with Claude Desktop, Cursor, Zed, and anything else that
speaks the [Model Context Protocol](https://modelcontextprotocol.io/).

```bash
npx -y @viveky/activity-mcp
```

The first run downloads a prebuilt, notarized macOS binary from the matching
[GitHub release](https://github.com/viveky259259/ai_activity_manager_macos/releases)
and verifies it against a baked-in SHA256. macOS-only (Intel + Apple Silicon).

## Wiring it into your MCP host

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "activity-manager": {
      "command": "npx",
      "args": ["-y", "@viveky/activity-mcp"]
    }
  }
}
```

**Cursor** (`~/.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "activity-manager": {
      "command": "npx",
      "args": ["-y", "@viveky/activity-mcp"]
    }
  }
}
```

**Zed** (`~/.config/zed/settings.json`):

```json
{
  "context_servers": {
    "activity-manager": {
      "command": { "path": "npx", "args": ["-y", "@viveky/activity-mcp"] }
    }
  }
}
```

## Tools

Read-only:

- `recent_projects(window)` → repos you touched, with hours and last seen
- `time_per_repo(window)` → ranked breakdown for a window
- `files_touched(repo, window)` → distinct files seen in IDE titles
- `current_context()` → repo / branch / file / app right now
- `current_activity()`, `timeline_range(...)`, `events_search(...)`,
  `app_usage(...)`, `list_rules(...)`, `list_processes(...)`

Write tools (`propose_rule`, `toggle_rule`, `kill_app`, `set_focus_mode`)
require the `ActivityManager.app` companion daemon and explicit user opt-in.

## What this needs to actually work

`activity-mcp` is the protocol surface. The data it serves comes from the
local capture daemon shipped with `ActivityManager.app`. Without the app
installed, capture-dependent tools return empty results. The full app is a
separate notarized DMG on the [Releases page](https://github.com/viveky259259/ai_activity_manager_macos/releases).

## License

MIT — see [LICENSE](../LICENSE).
