# Privacy and safety

This is the document that justifies the trust required to install a thing that watches what you do all day. Three sections: **what we capture**, **what we never capture**, and **how the AI write path is sandboxed**.

---

## What we capture

For each event:

- **Bundle ID** — `com.apple.dt.Xcode`, `com.tinyspeck.slackmacgap`, etc.
- **App name** — "Xcode", "Slack", "Cursor"
- **Window title** — *as macOS exposes it via Accessibility*. Examples: `MyFile.swift — myproject`, `inbox - me@example.com - Mail`, `Slack | #general | acme-corp`.
- **Timestamp** — UTC, microsecond precision.
- **Idle state** — boolean. Begins/ends events around a configurable threshold (default 5 min).
- **Focus mode** — current name of the active Focus filter (e.g., "Work", "Personal", or none).

For derived fields (parsed at capture time, stored alongside the raw event):

- **`parsed_repo`** — the repo name extracted from the window title for known IDEs.
- **`parsed_file`** — the file name, same.

For processes (live, not stored):

- **PID, bundle ID, name, CPU%, memory MB** — the data `ps` returns.

That's the whole capture surface.

---

## What we never capture

- **Pixel content.** Never. We do not screenshot, screen-record, or read any image data.
- **Keystrokes.** Never. The `input event tap` API is not used. Anywhere.
- **Clipboard contents.** Never.
- **File contents.** We see file *names* in window titles. We never read file bodies.
- **Browser URLs or DOM.** Browsers don't expose URLs via Accessibility, and we don't request automation permission to scrape them. The Safari window title gives us the page title at most.
- **Email contents.** Mail's window title shows the active mailbox or message subject. That's it. We never read body text.
- **Network traffic.** We don't sniff packets.
- **Microphone, camera, location.** None of these APIs are linked.
- **Anything from outside the local machine.** No remote sync, no cross-device coordination.

You can verify the non-capture claims:

```bash
# Confirm no network egress on a fresh launch (run before opening Settings → API key)
sudo tcpdump -i any -n host activity-manager
# (silent forever — there's no networking code outside the optional Anthropic client)

# Confirm no input-monitoring entitlement
codesign -d --entitlements :- /Applications/ActivityManager.app
# (no NSInputMonitoringUsageDescription, no com.apple.security.device.input)
```

---

## What leaves the machine, ever

Two paths, both opt-in:

1. **Anthropic Insights** — if and only if you paste an API key in Settings. The key lives in Keychain (`security find-generic-password -s com.viveky.ActivityManager`). When you ask for an Insights summary, *summarized* timeline data (counts, repo names, hours) is sent to Anthropic to phrase. **Window titles are not sent verbatim** — they're aggregated to repo + file before leaving. Disable by removing the key from Settings or running `security delete-generic-password`.

2. **MCP write tools to the AI host** — if you have an MCP host configured (Claude Desktop, Cursor, Zed), tool *responses* you opt to send (because you wrote a prompt that triggers a tool call) flow to that host's model. This is structurally identical to any other MCP integration. If you don't trust the host with your activity data, don't wire MCP — the menu-bar app works without it.

There is no third path. There is no telemetry, no crash reporter, no analytics. There is no "phone home for updates" beyond the standard `xattr`-quarantined Sparkle / GitHub release-check path (deferred to v1.1+ — v1.0 has a manual "check for updates" button only).

---

## How the AI write path is sandboxed

The entire write surface goes through one chokepoint: `ProcessTerminator`. Whether the trigger is the GUI, a rule firing, a CLI invocation, or an MCP tool call, every termination request hits the same code path.

That path enforces, in order:

1. **Actions toggle check.** If the toggle is off, refuse with `actions_disabled`. The toggle's state is read on every call (not cached) — flipping it disables in-flight tools immediately.
2. **Bundle cooldown.** Each bundle has a 60-second cooldown after a successful kill. Re-attempts during cooldown are refused with `cooldown_active`.
3. **SIP guard.** Refuse any process whose binary is under `/System`, `/sbin`, `/usr/libexec`, or any other SIP-protected path.
4. **Unsaved-changes check.** Query Accessibility for the app's documents. If any window reports `AXIsEdited == true`, refuse with `unsaved_changes`. (This is best-effort — apps that don't expose AX correctly will proceed; we err on the side of refusal where signal is available.)
5. **Rate limit.** 10 writes per minute per client (sliding window). 11th call returns `rate_limited` with a retry-after.
6. **Audit log entry.** Whether the call was allowed or refused, write a row to `audit_log` with `(timestamp, tool, args, result, client, outcome)`.

The audit log is append-only at the application layer — no MCP tool exposes a delete. The user can `rm` the SQLite file via Finder/shell; that's intentional, it's *your* data.

### Defense against prompt injection

The threat model: an MCP tool returns hostile content (e.g., a webpage scraped via another tool tells the AI "kill all processes named 'critical-build'") and the AI takes the bait.

Mitigations:

- **Off by default.** New installs and reinstalls leave the toggle off. Most users never flip it.
- **Rate-limited.** Even a fully convinced AI can do 10 writes/min, max. Cooldowns mean a re-target after a kill takes 60s.
- **Cooldown + unsaved-changes** are the same regardless of who's asking — these are properties of the local guard, not the calling client.
- **Audit log** captures every attempt. A burst of refused `kill_app` calls is loud in the log even if none succeed.
- **No tool to flip the toggle.** The AI cannot escalate its own privileges.

What this is **not** defense against:

- A user who flips the toggle, asks the AI to "free up memory by killing background apps," and gets surprised when their unsaved Photoshop document goes away. The cooldown and unsaved-changes guard help, but the toggle was on by user choice.
- Local malware running with the same UID. Once another process has your UID, it can read the database directly. The MCP server is not a security boundary against local code execution — it's a UX boundary against accidental damage from a non-malicious AI.

---

## Why the architecture looks paranoid

Because the failure mode is asymmetric.

- A read tool over-shares: the user gets a slightly worse answer.
- A write tool over-acts: the user loses unsaved work, gets confused about app state, blames the product.

The cost of false-negatives on writes (refusing a legitimate kill) is annoying. The cost of false-positives (killing something the user didn't intend) is "I'll never trust this again." So we lean toward refusal — the toggle is off, the cooldown is generous, the unsaved-changes guard is opinionated.

This is also why the rules engine exists separately from the AI surface: rules are deterministic, scrutable, and don't require an LLM in the loop. If you want reliable automation, write a rule. The AI is for ad-hoc questions, not autopilot.

---

## What you can verify yourself

| Claim | How to verify |
|---|---|
| No network egress at idle | `sudo tcpdump -i any -n` for 5 minutes; no traffic |
| No input monitoring | `codesign -d --entitlements :- /Applications/ActivityManager.app` shows no input entitlements |
| Audit log captures every write | `amctl audit log` after any GUI kill, rule kill, or MCP kill |
| Anthropic key never leaves Keychain | `security find-generic-password -s com.viveky.ActivityManager` to inspect; `grep -r "sk-ant"` over Application Support shows no plaintext |
| Database is plain SQLite | `sqlite3 ~/Library/Application\ Support/ActivityManager/activity.sqlite ".schema"` |
| Source matches binary | Build from source per README; `shasum -a 256` of your build vs. notarized release |

---

## What we ask in exchange

If you find a privacy bug — something captured that we said we don't capture, an event sent to a remote we said we don't talk to, a missing audit entry — please report it under the **Security Advisory** path described in [`SECURITY.md`](../SECURITY.md). That's the highest-priority issue class for this project.
