# Product Hunt — AI Activity Manager for macOS

> Submission template. Product Hunt rewards **specific outcomes** in the tagline and a **first comment from the maker** within minutes of launch.

## Name

**AI Activity Manager**

## Tagline (≤60 chars — pick one)

- **Local memory for your AI assistant. Open source. MCP.** (52)
- **Give Claude / Cursor / Zed memory of your real work.** (52)
- **An MCP server that remembers what you worked on.** (49)

> First option tested best — names the outcome ("memory"), the audience ("AI assistant"), and the trust posture ("open source") in a 60-char window.

## Topics

- Developer Tools
- Artificial Intelligence
- macOS
- Productivity
- Open Source

## Description

Your AI assistant has no memory of what you actually worked on yesterday. AI Activity Manager fixes that — a local timeline of every project, file, and app you touched, exposed to any MCP host through typed tools (`recent_projects`, `time_per_repo`, `files_touched`, `current_context`).

Ask Cursor *"summarize what I shipped this week"* — and the answer comes from real signals, not vibes.

Audited, rate-limited write surface. Destructive actions require a user-flipped toggle the AI cannot reach. **No telemetry. No App Store. Source is MIT.**

## Gallery (drop in this order)

1. **Hero shot** — Cursor conversation: *"what was I doing yesterday afternoon?"* → tool call expanded → 3 projects with hours + files. The `current_context()` response visible.
2. **Memory recall demo** — Claude Desktop calling `time_per_repo` over the last 7 days, getting a structured breakdown.
3. **Audit log** — Settings → Audit log tab showing the last 20 tool calls with timestamps, client, and result.
4. **Settings** — API key Keychain row, Actions opt-in toggle, walkthrough launcher. Make the safety toggles visible.
5. **Architecture diagram** — `docs/architecture.png` showing the inward-pointing dependency graph (or skip if not yet drawn).

## Maker's first comment (post within 60 seconds of go-live)

> Hi Hunters — Vivek here, the maker.
>
> Background: I kept asking Claude *"summarize what I shipped this week"* and getting noise back, because the assistant has no memory of what I actually did outside the chat. Git log only covers what got committed — most of my real work (review, design docs, debugging, the 90 min in Figma) lived nowhere structured.
>
> So I built the missing layer: a local timeline of your work that **any** MCP host can read. Same memory whether you're in Cursor, Claude Desktop, or your own agent. With explicit opt-in, the same surface lets the assistant act — close idle apps, change Focus mode — through the same safety rails the GUI uses.
>
> A few things I'd love feedback on:
>
> 1. **The dev-shaped MCP tool surface.** I picked `recent_projects` / `time_per_repo` / `files_touched` / `current_context` based on my own usage. What's missing? What's noise?
> 2. **The audited write path.** Every tool call is in a local audit log; rate-limited per client; writes need a user toggle. Is this the right ergonomic balance — or too much friction?
> 3. **Apple Foundation Models on-device.** Default for timeline Q&A. Anyone else shipping FM in production yet?
>
> Free, MIT. Direct DMG for the full Mac app, **`npx -y @viveky/activity-mcp`** if you only want the MCP surface (works on macOS 13+).
>
> Will be in the comments all day.
>
> — Vivek

## Posting checklist

- [ ] Schedule for **00:01 PT** (PH days reset at midnight Pacific)
- [ ] Pre-line up 5–10 supporters in the macOS / AI / open-source crowd
- [ ] First maker comment ready to paste; **don't** edit the tagline post-launch
- [ ] Linked: GitHub repo, demo video (60s, no voiceover), changelog, MIT license file
- [ ] Reply to **every** comment in the first 4 hours

## Hunter outreach (if you don't self-launch)

Personal DM works better than a tagged tweet. Template:

> Hey [name] — launching AI Activity Manager (open-source MCP server that gives Claude/Cursor/Zed memory of your real work) on Product Hunt next [Tue]. Free, MIT, `npx`-installable. Want to hunt it? Repo + 60s demo: [link]. Happy to do all the asset and comment-moderation lifting — just need you on the byline. — Vivek

## Common comment patterns to bake answers for

- *"Where's the demo video?"* — First asset in the gallery, not the third.
- *"Why MCP and not Shortcuts?"* — Shortcuts is great for one-shot automations; MCP is for streaming context to a reasoning loop. They compose: a Shortcut can call `amctl ask "..."`, which queries the same MCP surface.
- *"How is this different from Cursor's memory / Continue's context?"* — Those are host-scoped. This is a host-agnostic memory surface — same memory for Cursor, Claude Desktop, Zed, raw MCP tooling.
- *"Pricing?"* — Free, MIT, no Pro tier today. A team-tier (shared timeline, longer audit retention, SSO) is on the v1.1+ roadmap.
