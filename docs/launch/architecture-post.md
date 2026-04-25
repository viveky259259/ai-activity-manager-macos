# Designing an audited, rate-limited MCP write surface

> A long-form companion piece to the AI Activity Manager launch. Target audience: people building MCP servers that go beyond read-only tools. Working title for the repost: *"You'll regret it the day your MCP server gets prompt-injected."*

The hard part of shipping an MCP server isn't `tools/list`. The hard part is the day someone asks your assistant to *do* something — terminate a process, change a focus mode, write to a database — and a prompt-injected web page in another tab is asking the same model to do something you'd rather it didn't.

This is a walkthrough of the design choices we made in [AI Activity Manager](https://github.com/viveky259259/ai_activity_manager_macos) so that the same MCP host that gets an answer to *"what was I working on yesterday afternoon?"* can, with explicit opt-in, also act on it — and so that we can sleep through the night.

## The constraints we set

Before any code, we wrote down what we wanted to be true:

1. **Reads should be cheap and frictionless.** Anything an assistant asks the timeline should be answerable in milliseconds with no per-call permission prompts. Otherwise nobody uses it.
2. **Writes must be auditable forever.** Every `tools/call` that mutates state writes a row to a local audit log. Not "metric counters" — actual rows with the request payload and outcome. If something goes wrong I want a forensic trail.
3. **Writes must be rate-limited per client.** The model is not the attacker. The model is the *vector*. Anything within reach of a prompt — a webpage, an email, a file — could try to drive a runaway loop. Rate limits hold even if the model is fully compromised.
4. **Destructive actions must be off by default.** Toggling them on requires a human flipping a switch in a SwiftUI Settings pane. The AI cannot reach that pane. The MCP tool does not have an "enable yourself" verb.
5. **One safety chokepoint.** Whether the trigger is the GUI, a saved rule, an MCP tool call, or `amctl` from the shell — they all funnel through the same code path. Three separate kill paths with three separate cooldown logics is how you ship a bug.

These are deliberately strict. The first two are non-negotiable in a multi-tenant world. The last three are "do this once and never lose sleep about it."

## Layer by layer

### The MCP server

The stdio server is dumb on purpose. It speaks JSON-RPC, dispatches to a `ToolRegistry`, and gets out of the way. The registry is the only thing that knows whether a tool is enabled, whether it's a write, and what handler to call. Everything else — IPC, capture, persistence — lives behind a single `ActivityClientProtocol`.

```swift
public protocol ActivityClientProtocol: Sendable {
    func status() async throws -> StatusResponse
    func timeline(_ request: TimelineRequest) async throws -> TimelineResponse
    func events(_ request: EventsRequest) async throws -> EventsResponse
    // ...
    func killApp(_ request: KillAppRequest) async throws -> KillAppResponse
    func setFocusMode(_ request: SetFocusRequest) async throws
}
```

Production wires this to the named-XPC client. Tests wire it to a `FakeActivityClient` and run the same handler code. Three benefits:

1. Every tool's logic is unit-testable without a daemon.
2. Adding a new tool is a one-file change — write the `ToolDefinition`, register it, write a test using the fake.
3. A future Linux build of the MCP server can plug in a different transport without touching tool handlers.

### The audit log

Every `tools/call` that the handler dispatches lands in a SQLite-backed audit log:

```
client_id   | tool_name      | called_at  | request_json   | outcome      | took_ms
'cursor'    | 'kill_app'     | 1714065631 | {"bundle":"…"} | 'success'    | 12
'claude'    | 'propose_rule' | 1714065641 | {"nl":"…"}     | 'rate_limited' | 0
```

Three things matter about this:

- **Outcome is recorded for failures too.** A rate-limit denial is not "no audit row." It is an audit row that says `rate_limited`. That is the row you want when investigating "why did my MCP host suddenly start failing at 3am."
- **It's local.** No telemetry, no cloud, no opt-in dialog. The audit log is for the user, not the operator.
- **The audit log is the same regardless of trigger.** A GUI-triggered kill writes one row. A rule-triggered kill writes one row. An MCP-triggered kill writes one row. Same schema, same code path.

### The rate limiter

Two limits per client, default values from the PRD:

- **Reads:** 60 calls per rolling 60-second window
- **Writes:** 10 calls per rolling 60-second window

The limiter is keyed by `client_id`, which is whatever the MCP host announced during `initialize`. If a host doesn't announce one, it lives in a default bucket. The check happens *before* dispatch — a denied call never reaches the handler, never reaches the daemon, never touches the action surface. The denial is logged but the action is not performed.

The interesting design question was: should rate limits be per-tool, per-client, or per-tool-per-client? We picked per-client because the threat model is "someone drove this assistant in a runaway loop," not "someone made too many `recent_projects` calls." If you're making 60 reads/minute legitimately, fine. If you're making 60 writes/minute, no — even if they're spread across four different write tools.

### The single chokepoint

Killing a process can be triggered three ways:

1. The GUI — user clicks "Quit" in the menu bar, or a row in a debug panel.
2. A saved rule — "after 60 minutes of idle time, close iTunes."
3. An MCP `kill_app` tool call — model asked nicely.

If we wrote three implementations of "kill an app," we'd ship at least one of:

- A cooldown bug ("the GUI killed it 3 seconds ago and we're trying again")
- A SIP-guard bug ("we're trying to kill a system process")
- An unsaved-changes bug ("the user has a modal dialog open in this app")
- A logging bug ("the GUI path forgot to write an audit row")

So all three call sites delegate to a single `ProcessTerminator`:

- Looks up the bundle ID, validates it isn't a system process (SIP guard).
- Checks the per-bundle cooldown (default 30s — no thundering-herd kills).
- Probes for unsaved changes via the AX hierarchy. If found, downgrades the kill to a polite quit.
- Performs the action, returns an outcome enum.
- Writes the audit row.

The MCP `kill_app` tool is ~15 lines. It validates input, calls `ProcessTerminator`, returns the outcome. Add a fourth call site and it's the same call.

This is the single most important design decision in the whole project. Three kill paths × three safety checks each = nine places to forget one. One kill path × three safety checks = three things you write once.

## The opt-in toggle

Even with audit + rate limit + chokepoint, destructive actions ship **disabled by default**. Toggling them on is a switch in `Settings → Permissions`:

- Backed by `UserDefaults`, which the MCP server reads but cannot write.
- Reflected in `tools/list` — disabled write tools appear in the listing with a `disabled: true` marker, so the host can render the right UI affordance, but `tools/call` on a disabled tool returns a JSON-RPC error code `-32000` with `actions disabled`.
- The Settings panel itself shows the audit log inline. If you turn it on and 30 minutes later wonder what happened, the answer is one click away.

The toggle is not exposed as an MCP tool. There is no `enable_actions` verb. This is deliberate: an attack vector that gets you to flip the toggle is an attack vector that gets you keyboard control of the user's machine, at which point the threat model is no longer "MCP server."

## What I'd do differently

Three things I'd revisit if I were starting today:

1. **Per-bundle write rate limits.** Right now `kill_app` is governed by the global write limit. A future iteration probably wants "no more than 1 kill per bundle per 5 minutes" alongside the global cap. Today this lives in `ProcessTerminator`'s cooldown, not the rate limiter — fine in practice, slightly muddled in theory.
2. **Audit log retention policy.** Local-only is correct, but unbounded growth is a paper cut. v1 ships with 90-day retention; v1.1 will let the user configure it.
3. **A "shadow run" mode.** For new write tools, it'd be nice to log what they *would* do without actually doing it. Closest analog today is Rule mode `dryRun`, which works for rules but not ad-hoc tool calls. A future `tools/call` flag like `"shadow": true` would be a low-cost win.

## Why this matters beyond Activity Manager

If you're building any MCP server that mutates state — calendar, file system, infrastructure, billing — the same shape applies:

- Read tools should be ergonomic. Write tools should be auditable.
- The audit log is for the user, not the operator. Keep it local.
- Rate limit on the "who" (the client), not the "what" (the tool).
- Funnel side-effecting operations through a single chokepoint, no matter how they were triggered.
- Disable destructive actions by default. Make the opt-in path a thing the AI cannot reach.

None of this is novel. All of it is forgotten under launch pressure. Writing this design down before the first prompt-injection incident is a much better experience than writing it after.

— [Vivek](https://github.com/viveky259259) · `@viveky/activity-mcp` · MIT
