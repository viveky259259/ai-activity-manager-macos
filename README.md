# AI Activity Manager for macOS

**Local memory + audit log for your AI assistant.** Open source · MIT · MCP-native.

![Overview](docs/launch/assets/screenshots/01-overview.png)

Your AI assistant has no memory of what you actually worked on yesterday. AI Activity Manager fixes that — it captures a local timeline of every project, file, and app you touched, and exposes it to Claude, Cursor, Zed, or any MCP host through a typed tool surface. Ask *"what was I working on yesterday afternoon?"* and your assistant can answer from real signals — and, with explicit opt-in, act on them through the same safety rails the GUI uses.

- **Memory.** A local SQLite/FTS5 timeline of frontmost apps, window titles, idle state, and focus mode. Nothing leaves the machine.
- **MCP-native.** A stdio MCP server (`activity-mcp`) exposes typed tools — `recent_projects`, `time_per_repo`, `files_touched`, `current_context`, `query_timeline` — to any compliant host.
- **Audited & rate-limited writes.** Every `tools/call` lands in a local audit log. Per-client rate limits (60/min read, 10/min write). Destructive actions require an explicit user toggle the AI cannot flip.
- **Two LLM backends.** Apple Foundation Models on-device (macOS 26) for queries that never leave the network. Anthropic opt-in, key in Keychain.

## Install

### MCP server only (any AI dev — recommended)

```bash
# npx (zero-install — point your MCP host at this)
npx -y @viveky/activity-mcp

# Homebrew (persistent install of the standalone binaries)
brew tap viveky259259/tap
brew install activity-mcp amctl
```

Then add to your MCP host config:

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

Verify wiring:
```bash
amctl mcp doctor

# Or, for an interactive smoke test of every tool:
./Scripts/mcp-inspect.sh
```

The second command builds `activity-mcp` and launches the official
[MCP Inspector](https://github.com/modelcontextprotocol/inspector), which lets
you call `tools/list`, invoke each tool, and inspect raw JSON-RPC payloads —
the standard smoke test for any MCP server.

### Full macOS app (UI + menu bar)

1. Download the latest `ActivityManager.dmg` from [Releases](https://github.com/viveky259259/ai_activity_manager_macos/releases).
   Verify: `shasum -a 256 ActivityManager.dmg` matches the SHA256 published on the release.
2. Drag `ActivityManager.app` to `/Applications`.
3. Launch it. The menu-bar icon appears in the top right.
4. Open **Settings** → **Permissions** and grant what you want to use:
   - **Accessibility** — required for window-title capture (the part that knows which file/repo you're in).
   - **Calendar** — optional. Correlates calendar events with the timeline.
   - **Focus** — required to read/write Focus modes.
5. **Destructive actions are off by default.** Toggle "Actions enabled" in Settings only if you want rules or AI hosts to be able to terminate apps.

The full app bundles the MCP server, GUI, and CLI in one installer. The `npx` / `brew` paths above are for AI devs who only want the MCP surface.

## Recipes — copy-paste prompts for your assistant

**Morning standup**
> Using `recent_projects` and `files_touched`, summarize what I worked on yesterday in 5 bullets, grouped by project.

**Re-orient mid-day**
> Call `current_context` and tell me what I was doing 2 hours ago vs now. What's the through-line?

**Weekly review**
> For each repo I touched in the last 7 days, give me hours spent and the top 3 files I edited. Use `time_per_repo` and `files_touched`.

**Idle bloat sweep (writes — requires Actions enabled)**
> List apps over 1 GB I haven't touched in 60 minutes. Confirm with me before closing any.

### Agent system-prompt template

For folks wiring this into a custom agent rather than a chat host — drop this into your system prompt:

```
You have access to the user's local activity timeline through the
activity-manager MCP server. Treat its tools as ground truth for what
the user worked on; do not infer activity from chat history alone.

Read tools (use freely):
- recent_projects(window): repos touched, with hours and last-seen
- time_per_repo(window):   ranked breakdown for a window
- files_touched(repo, window): distinct files seen in IDE titles
- current_context():       repo / branch / file / app right now
- timeline_range, events_search, app_usage: lower-level recall

Rules:
1. Before summarizing the user's day/week, call recent_projects first.
2. When the user says "what was I doing": call current_context.
3. Never claim activity without evidence from a tool call.
4. Write tools (kill_app, set_focus_mode, propose_rule) require user
   opt-in and confirmation; never call them speculatively.
```

## Why this is interesting if you build with MCP

- The write-path design is in the open: every tool call is audited; per-client rate limits hold even under prompt-injection; the `ProcessTerminator` chokepoint enforces cooldown + SIP guard + unsaved-changes check whether the trigger is the GUI, a rule, or an MCP tool. See `docs/launch/architecture-post.md` for the long version.
- **Clean Architecture** — `Packages/ActivityCore` is pure domain (zero I/O, fully unit-testable). Everything macOS-y is an adapter behind a protocol. Easy to read, easy to extract.
- **No telemetry.** Zero. `tcpdump -i any -n` on a fresh launch is silent. The Anthropic provider only fires if you paste a key into Settings; key lives in Keychain.

## System requirements

| Component | macOS |
|---|---|
| `ActivityManager.app` (UI + on-device LLM) | macOS 26 (Tahoe) — required for Apple Foundation Models |
| `activity-mcp` (stdio MCP server, via npx or brew) | macOS 13+ |
| `amctl` (CLI) | macOS 13+ |

Apple Silicon recommended for the on-device LLM provider.

## Built with Activity Manager

Shipping something on top of `activity-mcp`? Open a PR adding it here. One-line entry, format:

```
- [Name](url) — what it does, what tools it uses
```

- _your project here — open a PR_

## Build from source

Requires Xcode 16+ and Swift 6.0+.

```bash
git clone https://github.com/viveky259259/ai_activity_manager_macos.git
cd ai_activity_manager_macos

# Run tests
swift test --package-path Packages/ActivityCore
swift test --package-path Apps/ActivityManager

# Build the app
swift build --package-path Apps/ActivityManager -c release

# Build the CLI + MCP server
swift build --package-path Apps/amctl       -c release
swift build --package-path Apps/activity-mcp -c release
```

### One-shot release build

```bash
# Local unsigned bundle:
./Scripts/build-release.sh

# Notarized DMG (requires the secrets repo cloned alongside this one):
./Scripts/build-release.sh --sign --dmg
```

The script reads `../../secrets/ai_activity_manager_macos/.env` for `DEVELOPER_ID_APP` and `AC_PROFILE` (one-time setup: `xcrun notarytool store-credentials AC_PROFILE`). Outputs land in `build/release/`.

Drop `Resources/AppIcon.icns` (auto-generated by `swift Scripts/generate-icon.swift`) and the script will embed it.

## Repository layout

```
Packages/
  ActivityCore/        Domain + use cases + ports. Zero I/O. Fully unit-testable.
  ActivityStore/       GRDB (SQLite + FTS5) adapter.
  ActivityCapture/     macOS capture sources (NSWorkspace, AX, EventKit, Focus).
  ActivityActions/     ProcessTerminator, FocusController, NotificationPoster.
  ActivityLLM/         LLMProvider protocol + Anthropic + FoundationModels.
  ActivityIPC/         Named XPC service + typed client/server.
  ActivityMCP/         MCP protocol handlers on top of the IPC client.
Apps/
  ActivityManager/     SwiftUI menu-bar app. Wires everything.
  amctl/               Command-line tool.
  activity-mcp/        MCP stdio server.
npm/                   npm wrapper that downloads the prebuilt binary.
homebrew/              Homebrew formulas for amctl + activity-mcp.
docs/
  prds/                Per-package product requirement documents.
  launch/              Launch assets — copy, demo script, architecture post.
```

## Principles

- **Clean Architecture** — dependencies point inward.
- **TDD** — Red → Green → Refactor. Never merge without tests.
- **Privacy-first** — local capture is non-negotiable; cloud LLM opt-in per feature; API key stored in macOS Keychain.
- **Safety-first actions** — destructive actions default to **off**; require explicit user opt-in plus per-bundle cooldown, SIP guards, and an unsaved-changes check before terminating.

## License

[MIT](./LICENSE)
