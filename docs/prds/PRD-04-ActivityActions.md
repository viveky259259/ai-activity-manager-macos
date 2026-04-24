# PRD-04 — ActivityActions

**Status:** proposed · **Depends on:** PRD-01 · **Blocks:** PRD-09

## 1. Purpose

Concrete `ActionExecutor` implementations for each `Action` case. All actions run under strict safety rails.

## 2. Executors

- `FocusModeController` — set/unset a Focus mode (deferred impl note: no public API to set Focus from 3rd-party; MVP will use Shortcut runner with user-authored "Set Focus to X" shortcut).
- `ProcessTerminator` — kill by bundle ID / pid with escalation.
- `AppLauncher` — `NSWorkspace.openApplication(at:...)`.
- `NotificationPoster` — `UNUserNotificationCenter`.
- `ShortcutRunner` — `shortcuts run <name>` via `Process`.
- `MessageLogger` — writes a `ruleFired` event into the store.

## 3. `ProcessTerminator`

### 3.1 Target resolution

```swift
public enum ProcessTarget: Hashable, Sendable {
    case bundleID(String)
    case processName(String)
    case pid(Int32)
}
```

Resolution strategy:
- bundleID → `NSWorkspace.runningApplications.filter { $0.bundleIdentifier == id }`
- processName → proc kinfo sweep via `sysctl` (non-sandboxed only)
- pid → direct

### 3.2 Strategy ladder

| Strategy | Impl |
|---|---|
| `.politeQuit` | `NSRunningApplication.terminate()` |
| `.forceQuit` | `NSRunningApplication.forceTerminate()` |
| `.signal(SIGTERM)` | `kill(pid, SIGTERM)` |
| `.signal(SIGKILL)` | `kill(pid, SIGKILL)` |

### 3.3 Escalation policy

1. Try requested strategy (default `.politeQuit`).
2. Wait up to `graceSeconds` (default 10 s).
3. If `force == true` and process still alive → escalate to `.forceQuit`.
4. Record each step into the store as a `ruleFired`-adjacent event.

### 3.4 Safety rails (hard-coded, cannot be overridden in v1)

- **SIP check**: never attempt to kill PIDs < 100 or processes with `com.apple.system` LaunchDaemon prefix.
- **Frontmost + unsaved**: inspect `kAXDocumentModifiedAttribute`; if `true` and strategy is destructive → return `.refused(reason: "unsaved changes")`.
- **Per-target cooldown**: 60 s default; cannot be overridden below 30 s.
- **Global kill switch**: if `ActionRegistry.actionsEnabled == false`, return `.refused(reason: "global kill switch")`.
- **Confirmation**: if rule's `confirm == .always`, post notification with Allow/Deny; await user choice with 30 s timeout → deny.

### 3.5 Outcomes

All outcomes persisted. Terminator returns one of:

```swift
public enum TerminationResult: Sendable {
    case terminated(pid: Int32, at: Date)
    case refused(reason: String)
    case notPermitted(reason: String)
    case notFound
    case escalated(from: String, to: String, TerminationResult)
}
```

## 4. Testing strategy

- `ProcessTerminator` behind a protocol with a **scripted fake** for unit tests:
  - Test: polite → refused (save dialog) with `force: false` → `.refused`.
  - Test: polite → no reply within 10s → escalation to force → `.terminated`.
  - Test: cooldown window blocks second attempt.
  - Test: SIP check rejects PID 50.
- Real impl has integration-only tests; guarded by `#if ACTIVITY_ACTIONS_LIVE`.
- `FocusModeController`: unit tests assert Shortcut invocation strings.
- `NotificationPoster`: unit tests via `UNUserNotificationCenter` mock.

## 5. Acceptance

- [ ] All safety rails tested with named unit tests.
- [ ] Escalation policy tested for all branches.
- [ ] Zero hard-coded bundle IDs or PIDs in rails (constants only).
- [ ] Every outcome emits an `ActivityEvent` of source `.rule`.
- [ ] Concurrency: two simultaneous kill requests to same target → one succeeds, one returns `.refused(reason: "cooldown")`.

## 6. Out of scope

- Privileged helper (`SMAppService.daemon`) — v1.1.
- Custom Focus mode authoring — requires user-authored Shortcut.
- Cross-user process management.
