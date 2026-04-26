# Launch posts — AI Activity Manager for macOS

## LinkedIn (long-form, B2B/dev tone)

I shipped something I've been wanting for myself: **AI Activity Manager for macOS** — local memory + audit log for your AI assistant.

The problem: Claude, Cursor, Zed — none of them have any memory of what you actually worked on yesterday. You end every conversation re-explaining context. Sound familiar?

What it does:
→ Captures a **local** timeline of every project, file, and app you touch (SQLite + FTS5, nothing leaves the machine)
→ Exposes that timeline as **typed MCP tools** — `recent_projects`, `time_per_repo`, `files_touched`, `current_context`, `query_timeline`
→ Works with Claude Desktop, Cursor, Zed, or any MCP-compliant host
→ Optional **rules engine** lets the assistant act — set Focus modes, kill distracting apps, run Shortcuts — all behind explicit user toggles, all rate-limited, all audited

Now you can ask *"what was I working on yesterday afternoon?"* and your assistant answers from real signals instead of guessing.

The bits I'm most proud of:
- **MCP-native from day one** — the AI integration is the product, not a bolt-on
- **Privacy-respecting by default** — Apple Foundation Models on-device (macOS 26) for the local path; Anthropic only on opt-in
- **Audited writes** — every `tools/call` lands in a local audit log; destructive actions need a toggle the AI cannot flip itself

Open source, MIT licensed. Built in Swift 6.2 with strict concurrency. macOS 26+.

Tap → https://github.com/viveky259259/ai-activity-manager-macos
Docs → https://viveky259259.github.io/ai-activity-manager-macos/

Would love feedback from anyone building MCP integrations or thinking about agent memory. What would you want a local activity layer to expose?

#opensource #macos #swift #mcp #modelcontextprotocol #ai #developertools #claude #cursor

---

## Reddit — r/MacOSApps (community-first, no marketing voice)

**[Open Source] AI Activity Manager — local memory + MCP server so Claude/Cursor/Zed can answer "what was I working on yesterday?"**

Hey folks. I built this because I got tired of re-explaining context to Claude every morning.

It's a menu bar app + a local MCP server. The app captures a private timeline of frontmost apps, window titles, idle state, and focus mode (all in SQLite, nothing leaves the machine). The MCP server exposes that timeline to any AI host as typed tools — `recent_projects`, `time_per_repo`, `files_touched`, `current_context`.

So you can ask Claude *"summarise yesterday afternoon"* and it actually knows.

Optional bits:
- **Rules engine** — JSON files like "if Slack quits, set Do Not Disturb"
- **Write tools** behind a separate toggle the AI cannot flip itself (set Focus, kill an app, run a Shortcut) — every call audited and rate-limited
- **Two LLM backends** — Apple Foundation Models on-device for the default path, Anthropic only if you opt in and paste a key

Stack: Swift 6.2, strict concurrency, SwiftUI menu bar app, stdio MCP server. macOS 26+.

Repo: https://github.com/viveky259259/ai-activity-manager-macos
Install via Homebrew: `brew tap viveky259259/tap && brew install activity-mcp amctl`
Or zero-install via npx in your MCP config: `npx -y @viveky/activity-mcp`

MIT licensed. Issues + PRs welcome.

---

## Reddit — r/ClaudeAI / r/LocalLLaMA (AI-native audience, lead with the problem)

**Made an MCP server that gives Claude memory of what you actually worked on**

Quick context: MCP (Model Context Protocol) lets you plug typed tools into Claude Desktop, Cursor, Zed, etc. I shipped one that exposes your local activity history.

Why: every Claude conversation starts with me typing "I'm working on X, the file is at Y, the bug is..." Same context, every time. The AI has no idea what I did 5 minutes ago.

So I built **AI Activity Manager** — a tiny menu bar app that records a local timeline (apps, windows, idle, focus mode) into SQLite, plus a stdio MCP server that exposes that timeline as tools:

- `recent_projects` — git repos you touched, ranked by recency
- `time_per_repo` — minutes per repo over a window
- `files_touched` — most-edited files
- `current_context` — what you're looking at right now
- `query_timeline` — full-text search over events
- 7 more

Now `"what was I doing yesterday afternoon"` works. So does `"how much time did I spend in the auth refactor this week"`.

Privacy: 100% local. Default LLM is Apple Foundation Models on-device (macOS 26). Anthropic only on opt-in.

There's also a write surface (set Focus mode, kill an app, run a Shortcut) but it's gated behind a separate toggle the AI cannot flip itself, every call is audited, and there are per-client rate limits. Default install is read-only.

Repo (MIT, Swift 6.2): https://github.com/viveky259259/ai-activity-manager-macos
Drop into Claude Desktop:
```json
{ "mcpServers": { "activity-manager": { "command": "npx", "args": ["-y", "@viveky/activity-mcp"] } } }
```

Curious what tools you'd want a local activity layer to expose. Calendar correlation? Browser history?

---

## Notes for posting

- LinkedIn: post Tuesday or Wednesday, 9–10am local. Tag #buildinpublic if comfortable.
- r/MacOSApps: weekly Showcase Saturday is the right slot — read sidebar rules; some subs require flair.
- r/ClaudeAI: post midweek, lead with the screenshot from `docs/launch/assets/screenshots/01-overview.png`.
- r/LocalLLaMA: lurk first — that sub is hostile to anything that looks like SaaS. Lead with "open source, MIT, runs locally."
- Always reply to the first 3–5 comments within an hour. Reddit's algo punishes drive-by posts.
