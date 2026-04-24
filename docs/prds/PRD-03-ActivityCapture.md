# PRD-03 — ActivityCapture

**Status:** proposed · **Depends on:** PRD-01 · **Blocks:** PRD-09

## 1. Purpose

Provide OS-level capture sources for macOS activity signals. Each source conforms to `CaptureSource` from ActivityCore and emits `ActivityEvent`s into its `AsyncStream`.

## 2. Sources (MVP)

| Source | API | Entitlement |
|---|---|---|
| `FrontmostAppSource` | `NSWorkspace.shared.frontmostApplication` + `NSWorkspaceDidActivateApplicationNotification` | none |
| `WindowTitleSource` | AX: `AXUIElementCreateApplication` → `kAXFocusedWindowAttribute` → `kAXTitleAttribute` | Accessibility (TCC) |
| `IdleSource` | `CGEventSourceSecondsSinceLastEventType` | none |
| `CalendarSource` | EventKit `EKEventStore` + `EKEventStoreChanged` notification | Calendar access (TCC) |
| `FocusModeSource` | `INFocusStatusCenter` KVO | Focus status auth |
| `RunningAppsSource` | `NSWorkspace.runningApplications` + launch/terminate notifications | none |

## 3. Sources (deferred to v1.1)

- `BrowserURLSource` (per-browser AX + AppleScript fallback).
- `ScreenshotOCRSource` (ScreenCaptureKit + Vision).

## 4. Orchestration

`CaptureCoordinator`:

- Owns the set of active sources.
- Merges their `AsyncStream`s into a single `AsyncStream<ActivityEvent>`.
- Handles restart with exponential backoff on `start()` failure.
- Exposes `currentStatus: [SourceID: SourceStatus]` for the UI.

## 5. Sampling policy

| Signal | Cadence |
|---|---|
| Frontmost app | event-driven + 30 s heartbeat |
| Window title | 2 s debounce while focus stable |
| Idle | 10 s poll |
| Calendar | event-driven on EKEventStoreChanged |
| Focus mode | event-driven (KVO) |

## 6. Permissions flow

`PermissionsChecker` (in `ActivityCapture` package) exposes:

```swift
public enum Permission { case accessibility, calendar, focus, automation(bundleID: String) }
public enum PermissionStatus { case granted, denied, notDetermined }

public protocol PermissionsChecker: Sendable {
    func status(for: Permission) -> PermissionStatus
    func openSettings(for: Permission)
}
```

## 7. Testing strategy

- Pure-logic units (e.g. `IdleGate` that collapses raw idle samples into idle spans) — 100% unit tested.
- OS-adapter units — behind `FakeSystem` protocol where possible (NSWorkspace wrapper injection).
- Live-verification harness — a small test target that runs on-device and asserts at least one event is captured within 5 seconds. Documented as **NOT** part of CI.

## 8. Acceptance

- [ ] `CaptureCoordinator` merges ≥ 2 sources without lost events under 1000 events/sec burst.
- [ ] `IdleGate` unit tests cover: no idle, idle mid-period, idle crossing threshold multiple times.
- [ ] `FrontmostAppSource` scripted-fake test: app switch → one `frontmost` event emitted with correct bundleID.
- [ ] Permissions check returns correct status for each permission type.
- [ ] Zero AX calls on main thread (verified by unit test with main-thread checker).

## 9. Out of scope

- Screenshot capture + OCR.
- Browser-specific URL adapters.
