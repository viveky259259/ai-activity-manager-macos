# Demo Script — 60 second product video

Goal: in one minute, prove that an AI assistant can recall **what you actually worked on** from a local memory it has typed, MCP access to — and (only at the very end, as a supporting beat) act on that memory through audited, rate-limited tools.

> **Total runtime target: 0:60** · No voiceover. Captions only. Background music low-fi.
>
> Resolution: 1920×1080, 60fps. Record in macOS dark mode for contrast.

## Storyboard

| Time | Scene | What's on screen | Caption |
|---|---|---|---|
| 0:00–0:04 | Cold open | Cursor open, mid-afternoon. User types: *"summarize what I shipped this week"*. Cursor responds with a vague, useless summary — generic phrases, no specifics. | *"Your AI doesn't know what you worked on.<br/>Until now."* |
| 0:04–0:08 | Title card | App icon + "AI Activity Manager" wordmark. Tagline: *"Local memory for your AI assistant. Open source. MCP."* | — |
| 0:08–0:14 | The install (compressed) | Terminal: `npx -y @viveky/activity-mcp` (one line). Switch to Cursor settings → MCP → green dot next to `activity-manager`. Restart hint dismissed. | *"One command.<br/>Any MCP host: Claude Desktop, Cursor, Zed."* |
| 0:14–0:26 | Memory recall — the win | Same Cursor conversation: re-ask *"summarize what I shipped this week"*. Cursor calls `recent_projects(window: 7d)` → expands tool call → returns 3 repos with hours. Cursor calls `files_touched(repo: "auth-service", window: 7d)` → 8 files. Cursor writes a real summary: hours per repo, top files, what changed. | *"recent_projects · time_per_repo · files_touched<br/>real signals, not vibes"* |
| 0:26–0:36 | The deeper recall | Type *"what was I doing yesterday at 3pm?"*. Cursor calls `current_context(at: "yesterday 15:00")` → returns repo + branch + file + app. Cursor: *"You were in `auth-service` on branch `oauth-refactor`, in `routes/login.swift`, in Cursor."* | *"Your assistant gets back into context<br/>before you do."* |
| 0:36–0:46 | The action (kept short) | Type *"close iTunes — it's been idle for 2 hours"*. macOS permission banner: *"ActivityManager wants to terminate iTunes."* User clicks Allow. iTunes closes. Audit log entry appears in Settings. | *"Off by default.<br/>Cooldown · SIP guard · audit log on every call."* |
| 0:46–0:54 | Privacy beat | Settings panel — Anthropic key field empty. "On-device LLM (Apple Foundation Models)" toggle on. Audit log tab visible with 4 entries. "No telemetry" badge. | *"No telemetry.<br/>API key in Keychain.<br/>Cloud is opt-in."* |
| 0:54–1:00 | End card | GitHub URL + *"Free · MIT · `npx -y @viveky/activity-mcp`"* + QR code linking to the repo. | *"github.com/viveky259259/<br/>ai_activity_manager_macos"* |

## Recording checklist

- [ ] **Clean macOS profile.** Fresh `demo-user` account so notifications, Dock, and wallpaper are pristine.
- [ ] **Pre-stage real work signal.** Before recording, spend 30–45 minutes in 2–3 actual repos so the timeline has substance. The `recent_projects` response only sells the demo if the rows look real.
- [ ] **Pre-grant TCC permissions.** Walkthrough the app once before recording so no permission sheets interrupt.
- [ ] **Disable notifications.** Do Not Disturb on; quit Slack, Mail, Messages.
- [ ] **Hide menu-bar clutter.** Bartender / Hidden Bar — only the ActivityManager icon visible.
- [ ] **Cursor visibility.** Record at 60fps so the cursor reads as smooth motion.
- [ ] **Edit out the install wait.** Jump-cut from `npx` to the post-install Cursor MCP panel.
- [ ] **Fake-but-real screenshots only.** Don't fabricate timeline data. If the demo-user account doesn't have enough history, run the recording session itself for 60 minutes first, then come back to record the demo.
- [ ] **Captions in SF Pro.** Bottom-third overlay, 48pt, semi-bold, white-on-black 70% opacity.

## Cuts to keep on the floor

- The first-run walkthrough sheet — too much text for 60s. (Save it for a separate "first-run" video.)
- The full Settings → Permissions tour — same reason.
- Any `swift test` shots — devs will go to GitHub for that.
- The "RAM cleanup" framing — replaced entirely with the memory-recall framing. The terminate-iTunes beat stays in for 10 seconds as a *capability* demo, not as the headline.

## Assets to export

- `docs/launch/assets/demo-60s.mp4` — primary
- `docs/launch/assets/demo-60s-muted.mp4` — for X/LinkedIn autoplay
- `docs/launch/assets/demo-thumbnail.png` — 1280×720, captures the 0:24 beat with `recent_projects` results visible
- `docs/launch/assets/demo-15s.mp4` — TikTok/Reels cut: 0:14–0:26 only (the install + the recall win), with louder caption typography

> The 15-second cut is what wins on social — install + the moment Cursor returns real project hours. The full 60-second is for the README and Show HN comments.

## A note on the headline beat

The 0:00 cold open exists to make a non-AI-developer audience understand the problem. For an AI-dev audience the framing is *already* obvious — they hit this every day. If you're cutting a *separate* dev-only edit for Latent Space or the Anthropic Discord, drop the cold open and start from 0:14 (the install + recall) for a 30-second cut. That edit's caption: *"Memory for your assistant. One command. Any MCP host."*
