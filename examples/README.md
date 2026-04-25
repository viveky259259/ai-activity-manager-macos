# Examples

Runnable samples for the three primary surfaces of Activity Manager:

| Folder | What's in it | Who it's for |
|---|---|---|
| [`rules/`](./rules) | JSON snippets you can paste into the Rules tab | Anyone using the GUI |
| [`mcp/`](./mcp) | JSON-RPC requests for `activity-mcp` (curl-able) | MCP host integrators |
| [`amctl/`](./amctl) | Shell snippets for the `amctl` CLI | Terminal/scripting users |

Each folder has its own README explaining the example, the expected output,
and the required permission state (e.g. *"Actions enabled = OFF is fine"* or
*"Requires Accessibility permission"*).

## Quickstart by use case

- **"Show me what I worked on yesterday afternoon"** →
  [`mcp/recent-projects.json`](./mcp/recent-projects.json) or
  [`amctl/recent-projects.sh`](./amctl/recent-projects.sh).
- **"Switch to Focus mode automatically when Slack is closed"** →
  [`rules/auto-focus-when-slack-closed.json`](./rules/auto-focus-when-slack-closed.json).
- **"Notify me when I've been on YouTube for 30 min"** →
  [`rules/youtube-30min-warn.json`](./rules/youtube-30min-warn.json).
- **"Connect Activity Manager to Claude Desktop"** →
  [`mcp/claude-desktop-config.json`](./mcp/claude-desktop-config.json).
