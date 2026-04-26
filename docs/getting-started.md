# Getting started — first 10 minutes

This walks you from "downloaded the DMG" to "Claude can answer *what was I working on yesterday*". Pick the path that matches your situation.

---

## Path A — I want the full app (UI + menu bar + AI features)

Best for: regular users who want the timeline UI, Insights, and rules.

### 1. Install

```bash
# Option 1 — direct download
# Get ActivityManager.dmg from
#   https://github.com/viveky259259/ai-activity-manager-macos/releases
# Verify SHA256 matches the release page, then drag to /Applications.

# Option 2 — Homebrew
brew tap viveky259259/tap
brew install --cask activity-manager
```

### 2. First launch

- The menu-bar icon appears in the top-right.
- A first-run **Onboarding** sheet walks you through:
  - **Welcome** → why this exists and what it captures
  - **Permissions** → grant Accessibility (window titles), optionally Calendar, Focus
  - **Optional API key** → paste your Anthropic key if you want cloud-LLM Insights. **Skip this** if you're on macOS 26 — Apple Foundation Models runs on-device and is the default.
  - **Actions opt-in** → leave OFF unless you want rules/AI to terminate apps

You can change any of these later in Settings.

### 3. Verify it's working

Open the menu-bar icon → click "Show Activity Manager". You should see:
- **Overview** tab populated within 30 seconds (live process list + timeline strip)
- **Timeline** tab showing recent app/window events
- **Settings → Permissions** all green for what you granted

If the Overview tab is empty after a minute, run `amctl status` from Terminal and check that the daemon is sampling. Common cause: Accessibility permission denied — re-grant in System Settings → Privacy & Security → Accessibility.

### 4. (Optional) Wire it into your AI host

The full app bundles `activity-mcp`. Add to your AI host's config:

**Claude Desktop** — `~/Library/Application Support/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "activity-manager": {
      "command": "/Applications/ActivityManager.app/Contents/Resources/activity-mcp"
    }
  }
}
```

Restart Claude Desktop. In a new chat, ask *"What MCP tools do you have available?"* — you should see `activity-manager` listed with 12 read tools.

---

## Path B — I just want the MCP server for my AI assistant

Best for: AI devs and tinkerers who don't need the GUI.

### 1. Install the standalone binary

```bash
# Zero-install (npx)
# This works in your MCP host config without installing globally:
#   "command": "npx", "args": ["-y", "@viveky/activity-mcp"]

# Or persistent install via Homebrew
brew tap viveky259259/tap
brew install activity-mcp amctl
```

### 2. Wire into your AI host

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
```jsonc
{
  "context_servers": {
    "activity-manager": {
      "command": { "path": "npx", "args": ["-y", "@viveky/activity-mcp"] }
    }
  }
}
```

Or let `amctl` merge the JSON for you:
```bash
amctl mcp install claude-desktop
amctl mcp install cursor
amctl mcp install zed
```

### 3. Verify wiring

```bash
amctl mcp doctor
```

This checks the binary is on PATH, the config is wired correctly, and the server boots and responds to `tools/list`. All-green output looks like:

```
✓ activity-mcp binary present  (~/.cargo/.../activity-mcp v1.0.0)
✓ claude-desktop config wired  (~/Library/Application Support/Claude/...)
✓ server boots and responds    (12 read tools, 4 write tools)
```

For an interactive smoke test — launches the official MCP Inspector against a fresh build:

```bash
./Scripts/mcp-inspect.sh
```

### 4. First prompt

In your AI host, try:

> Call `current_context` and tell me what app I'm in and what file (if any) I have open.

If the assistant returns a real bundle ID + window title, you're done.

---

## Common first-run gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Overview tab empty after a minute | Accessibility permission missing | System Settings → Privacy & Security → Accessibility → enable ActivityManager |
| `current_context` returns null repo | Window-title parser doesn't recognize your IDE | We support Cursor, VSCode, Xcode, Zed, JetBrains, Terminal, iTerm — open an issue with a screenshot of the title bar if your IDE is missing |
| `amctl mcp doctor` says "server fails to boot" | Stale config pointing at an old path | `amctl mcp install <host>` overwrites the config block in place |
| Insights tab says "no LLM provider" | macOS &lt;26 and no Anthropic key | Either upgrade to macOS 26 (free) or paste an Anthropic key in Settings |
| Claude says "no tools available" after wiring | Forgot to restart Claude Desktop | Cmd-Q the app, reopen |
| `kill_app` returns "actions disabled" | Actions toggle is off (the safe default) | Settings → Actions → enable. Audit log captures every call from then on. |

---

## Next steps

- Read [`use-cases.md`](use-cases.md) for concrete prompts that work today
- Read [`concepts.md`](concepts.md) to understand sessions, the actions toggle, rate limits
- Read [`reference.md`](reference.md) for the full MCP tool + CLI surface
