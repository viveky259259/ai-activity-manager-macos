# Launch-day social copy

A bank of posts for X/Mastodon/LinkedIn/Threads. Pick **one** as the launch anchor; the rest are follow-ups across the launch week.

## Anchor post (X / Mastodon — fits 280)

> Shipping **AI Activity Manager** today.
>
> Open-source macOS app that lets Claude (or Cursor, or Zed) see what's running on your Mac and, with your opt-in, close the apps eating your RAM.
>
> No telemetry. MIT. Direct DMG.
>
> github.com/viveky259259/ai_activity_manager_macos

## Anchor post (LinkedIn — longer-form OK)

> After 6 months of nights-and-weekends, **AI Activity Manager v1.0 is shipping today.**
>
> The pitch in one sentence: a local timeline of everything happening on your Mac, plus an MCP server that lets your AI assistant read it — and, with explicit opt-in, act on it.
>
> Why I built it: Activity Monitor tells you Slack is using 3 GB. Cool. Now what? I wanted to *ask* my assistant to clean it up — and have it actually be able to.
>
> What it is:
> · Swift-native menu-bar app for macOS 26
> · Stdio MCP server in the same bundle (`activity-mcp`) — works with Claude Desktop, Cursor, Zed
> · Apple Foundation Models on-device for timeline Q&A; Anthropic opt-in for richer reasoning
> · Destructive actions off by default; cooldown, SIP guard, unsaved-changes check, and audit log on every tool call
>
> What it isn't:
> · Telemetry-collecting (zero — this is a contract, not a slogan)
> · App Store-distributed (Apple disallows this kind of background helper)
> · Free + Pro tiered (it's MIT, top to bottom)
>
> Direct download: [link to release]
> Source: github.com/viveky259259/ai_activity_manager_macos
>
> Would love your feedback — especially on the safety-rail design and the MCP write-path ergonomics.

## Follow-up bank (one per day for launch week)

### Day 1 — the demo

> 60 seconds: from "my Mac is sluggish" to "Claude closed the 4 idle apps eating 3.2 GB" — through the same safety rails the GUI uses.
>
> [embed demo-60s.mp4]
>
> github.com/viveky259259/ai_activity_manager_macos

### Day 2 — privacy receipts

> "No telemetry" is easy to say and hard to prove. So:
>
> 1. `tcpdump -i any -n` on launch — silence
> 2. Anthropic key only fires if **you** paste one in Settings; stored in Keychain
> 3. The MCP audit log is local-only, owned by your user account
>
> Open source so you can verify all three.

### Day 3 — the architecture beat

> Things I'm proudest of in v1.0:
>
> · Domain (`Packages/ActivityCore`) has zero I/O. Everything macOS-y is an adapter.
> · `ProcessTerminator` is the single chokepoint for every "kill this app" path — GUI rule, AI tool call, CLI command. One safety implementation; three call sites.
> · MCP write tools are gated on a user toggle the AI literally cannot flip.
>
> Clean Architecture + MCP = surprisingly tidy.

### Day 4 — the CLI cameo

> Forgot to tweet about `amctl`. It's the CLI in the same bundle. Some favorites:
>
> ```
> amctl ps --idle 30m --over 1gb
> amctl timeline --last 1h
> amctl mcp install claude-desktop
> amctl mcp doctor
> ```
>
> Built for keyboard-first folks; the GUI is for everyone else.

### Day 5 — the open-source ask

> Day 5 of launch week. The repo crossed [N] stars, [M] DMG downloads, [K] Issues filed.
>
> If you'd like to help: I'm prioritizing the v1.1 list based on Issue 👍 reactions. Top-voted right now is [issue title]. Add yours.
>
> github.com/viveky259259/ai_activity_manager_macos/issues

## Hashtags / handles

> Use sparingly — one or two max per post.

- `#macOS` `#opensource` `#MCP` `#ClaudeAI`
- `@anthropicai` only on posts that talk about Anthropic specifically
- `@MacStoriesNet` only after MacStories has covered (no pre-tagging)

## Threads variant

Threads runs longer than X. The Day 1 anchor expands well there — split it into 4 posts: (1) the pitch, (2) the demo gif, (3) the privacy beat, (4) the link.

## Launch-day timing

| Time (PT) | Channel | Action |
|---|---|---|
| 00:01 | Product Hunt | Submission goes live |
| 06:00 | LinkedIn | Long-form anchor post |
| 08:30 | Show HN | Submit (peak HN ranking window) |
| 09:00 | X / Mastodon | Anchor post + reply with PH link + reply with HN link |
| 11:00 | Threads | 4-post thread |
| 14:00 | r/macapps | Self-post with 60s demo embed |
| 16:00 | Reply sweep | Backfill replies on every channel |

## Don't post

- Anything that reads as a sales funnel — there's nothing to sell. The whole product is on the GitHub release page.
- "Excited to announce" — the word "excited" weakens the post.
- Emojis in the first 140 chars of any X post — algorithmic deboost.
