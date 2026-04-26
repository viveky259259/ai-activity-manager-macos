# Overview — what this is, and what it isn't

## The problem

Your AI assistant has no memory of what you actually did yesterday. Every Claude / Cursor / Zed session starts the same way: you re-explain context, paste file paths, list which repo you were debugging, and hope it sticks for the next 20 minutes.

The fix isn't bigger context windows. The fix is a **separate memory layer the AI can query** — one that observes what you actually do (apps, files, repos, focus state) and exposes it as a typed tool surface the model can call when it needs to ground a response.

## The shape of the solution

AI Activity Manager is three things that work together:

1. **A capture layer** — a tiny menu-bar agent that records frontmost app, window title, idle state, and Focus mode into a local SQLite database (with FTS5 for search). Nothing leaves the machine.
2. **An MCP server** — `activity-mcp`, a stdio Model Context Protocol server that exposes the timeline as **12 read tools** (`recent_projects`, `time_per_repo`, `files_touched`, `current_context`, `query_timeline`, …) and **4 write tools** (`kill_app`, `create_rule`, `update_rule`, `delete_rule`).
3. **A safety layer** — every write goes through one chokepoint (`ProcessTerminator`) that enforces a per-bundle cooldown, a SIP guard, and an unsaved-changes check. Writes are off by default, gated behind a Settings toggle the AI cannot flip itself, and rate-limited per client (60/min read, 10/min write). Every `tools/call` lands in a local audit log.

The product surface is a menu-bar app with Overview / Processes / Timeline / Rules / Insights / Settings tabs, plus a command-line tool (`amctl`) that mirrors the read surface for shell scripting.

## What it actually feels like

After install + permissions, the menu-bar icon shows a tiny live activity indicator. Click it for a 30-min timeline strip. Open the full app for the timeline (full-text searchable), per-process CPU/memory, and an Insights tab that asks the LLM "what did I do this week?"

Wired into Claude Desktop, your morning standup looks like:

> **You:** What did I work on yesterday afternoon?
>
> **Claude:** *(calls `query_timeline` and `time_per_repo`)* Between 2:00 PM and 5:30 PM you were primarily in `viveky259259/ai-activity-manager-macos`, mostly on `Packages/ActivityMCP/Sources/ReadTools.swift` and the test snapshots beside it. You took a 25-minute break around 3:45 (Focus mode flipped to Personal, frontmost was Slack), then came back to the same files.

That answer is grounded in real data, not a paraphrase of your last chat message.

## What it isn't

- **Not a SaaS.** No account, no cloud sync, no telemetry. `tcpdump -i any -n` on a fresh launch is silent.
- **Not a time tracker for billing.** It's a memory substrate, not a Toggl/Harvest replacement. There's no invoice export, no team rollups.
- **Not an autonomous agent.** The AI cannot do destructive things on your machine unless you flip the Actions toggle, and even then there are rate limits, cooldowns, and an audit log.
- **Not a productivity coach.** It records and answers questions. It doesn't nag, gamify, or score you.
- **Not a screenshot recorder.** It captures structured signals (bundle ID, window title, idle/focus state) — not pixels, not keystrokes, not URLs.

## Who it's for

- **Solo devs and indie hackers** who use Claude / Cursor / Zed daily and are tired of re-explaining context every session.
- **AI tinkerers** building agents on top of MCP who want a real, non-toy local data source to integrate.
- **Privacy-minded macOS power users** who want a local timeline without a cloud product attached.

It's *not* aimed at: enterprise time-tracking buyers, teams that need shared dashboards, people on Linux/Windows (yet).

## How it differs from things you may have used

| Tool | What they do | What we do differently |
|---|---|---|
| **RescueTime / Toggl** | Cloud-based time tracking, billing-focused | Local-only, no account, AI-queryable |
| **ActivityWatch** | Open-source local time tracker | We add a typed MCP surface so AI assistants can read & act |
| **Raycast / Alfred** | Launcher + workflows | We're a memory layer, not a launcher; complementary, not competing |
| **Apple Screen Time** | Built-in usage stats | We're per-window/per-repo and exposed as tools, not a settings panel |
| **Memory features in chat apps** | "Remember that I prefer X" notes | We capture *signals*, not preferences — what you did, not what you said |

## Mental model

Think of it as **a journal your computer writes for you, with an API**. The journal is in SQLite. The API is MCP. The writer is a 30 MB menu-bar agent. The reader is whatever AI assistant you trust enough to grant access.

That's the whole thing. The rest is implementation detail (which the rest of these docs cover).
