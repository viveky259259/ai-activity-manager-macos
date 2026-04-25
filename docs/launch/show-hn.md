# Show HN — AI Activity Manager for macOS

> Submission template for `news.ycombinator.com/submit`. Pick **one** title; paste the body verbatim.

## Title (≤80 chars; pick one)

- **Show HN: An MCP server that gives your AI assistant memory of your work on macOS**
- **Show HN: Local memory + audit log for Claude/Cursor/Zed (open source, MCP)**
- **Show HN: AI Activity Manager — your Mac's timeline as a typed MCP surface**

> Pick the one that reads best the morning of launch — usually the most concrete first noun ("memory") wins over the vague one ("manager").

## URL

`https://github.com/viveky259259/ai_activity_manager_macos`

## Text (leave URL field set; HN convention is "text empty when URL is set")

If the title is borderline ambiguous, post as a text post and put this in the body:

---

**AI Activity Manager** is an open-source macOS app that gives your AI assistant a local, structured memory of what you actually worked on.

The core problem I kept hitting: I'd ask Claude or Cursor *"summarize what I shipped this week"* and the answer was useless, because the assistant has no memory outside the conversation. Git log helps, but most of my work isn't visible in commits — code review, design docs, debugging sessions, the 90 minutes I spent in a Figma file.

So I built the missing layer:

1. **Local timeline.** Frontmost app, idle state, focus mode, and (with Accessibility permission) window titles get captured into a SQLite/FTS5 database. Window titles in Cursor/VSCode/Xcode/Zed expose the file path and repo, so the timeline knows which project you were in. Nothing leaves the machine — no telemetry, no crash reporting, no remote config.
2. **MCP server.** A bundled stdio MCP server (`activity-mcp`) exposes typed tools to Claude Desktop, Cursor, Zed, or anything that speaks MCP:
   - `recent_projects(window)` → projects you touched grouped by repo
   - `time_per_repo(window)` → hours per repo over the window
   - `files_touched(repo, window)` → files you actually had open
   - `current_context()` → repo / branch / file / app right now
   - `query_timeline(...)`, `top_apps(...)` — the broader surface for free-form recall

So *"what was I working on yesterday afternoon when I was deep in [thing]?"* now has an answer. And *"close iTunes and Photos, they've been idle for an hour"* works too — through the same safety rails the GUI uses.

The interesting design beats:

- **Audited, rate-limited writes.** Every `tools/call` lands in a local audit log. 60/min reads, 10/min writes, per-client. Destructive actions require a user-flipped toggle the AI literally cannot reach.
- **One chokepoint for kills.** GUI rule, MCP tool call, CLI — all funnel through `ProcessTerminator`, which enforces cooldown, SIP guard, unsaved-changes check, and a kill switch. One safety implementation; three call sites.
- **Two LLM backends.** Apple Foundation Models on-device (macOS 26) for queries that never touch the network. Anthropic opt-in, key in Keychain.
- **Clean Architecture.** `Packages/ActivityCore` is pure domain — zero I/O, fully unit-testable. The macOS-y stuff (NSWorkspace, AX, EventKit, GRDB, XPC) lives in adapters. Reference-quality if you're shipping your own MCP server.

Stack: Swift 6 strict concurrency, GRDB + FTS5, NSXPC for the helper, MCP over stdio. Direct DMG (notarized) for the full app. **`npx -y @viveky/activity-mcp`** if you only want the MCP surface — works on macOS 13+. Source is MIT.

There's a longer write-up of the audit-log + write-surface design in `docs/launch/architecture-post.md` — happy to dig into it in the comments.

— Vivek

---

## Posting checklist

- [ ] Post between **8:00–10:00 AM Pacific** on a Tuesday/Wednesday/Thursday for best ranking
- [ ] Reply to the first 5 comments within 15 minutes
- [ ] Have the README ready — most clickers go straight there
- [ ] Have the demo video (`docs/launch/demo-script.md`) embedded in the README
- [ ] If asked "why MCP and not [X]?" — point to the audit log + rate-limit + opt-in-write design

## Common questions to pre-bake answers for

- *"Why isn't this in the App Store?"* — App Store guideline 2.4.5 disallows background helpers that monitor other apps. Direct DMG, notarized, hardened runtime. (The MCP-server-only path via `npx`/`brew` is unaffected.)
- *"What does it send to Anthropic?"* — Only what you ask it. Provider defaults to `.null`; the cloud key is opt-in. Redactor pass before any prompt leaves the machine.
- *"Can I run just the MCP server?"* — Yes. `npx -y @viveky/activity-mcp` or `brew install activity-mcp`. The Mac UI is optional.
- *"How is this different from Cursor's memory / Continue's context?"* — Those are scoped to their own host. This is a host-agnostic memory surface — query it from Claude Desktop, Cursor, Zed, raw `mcp` tooling, your own agents. Same memory; many readers.
- *"Why not cross-platform?"* — Most of the value is in macOS-specific signals (frontmost app, idle, AX, Focus). Linux MCP-only build of the server is on the roadmap.
