# PRD-09 — ActivityManager menu-bar app

**Status:** proposed · **Depends on:** PRD-02, 03, 04, 05, 06 · **Blocks:** none

## 1. Purpose

SwiftUI menu-bar app. Wires every adapter, hosts the `ActivityIPC` server, renders the timeline, runs the rule editor and chat/query panel, and owns the onboarding flow.

## 2. Surfaces

### 2.1 Menu-bar extra

- Shows current activity (icon + bundle name, optional duration).
- Quick actions: Pause capture, Toggle Actions, Open Timeline, Open Settings, Quit.
- Global status dot: green (all sources ok), yellow (some permissions missing), red (capture failed).

### 2.2 Timeline window

- Day/week scrubber.
- Session list virtualized by hour.
- Click session → details drawer (attributes, OCR text when enabled).
- Search bar → FTS query.
- Chat panel (right side) → `timeline_query` answers with in-line citations.

### 2.3 Rule editor

- List view of rules with state badge (dryRun / active / disabled).
- Create new → NL input → calls `CompileRuleFromNL` → shows compiled DSL → user can edit → save in dryRun.
- Detail pane: recent firings, dry-run stats, edit DSL directly (Monaco-style JSON editor).

### 2.4 Settings

- Permissions status (Accessibility, Calendar, Focus).
- LLM provider settings (API keys, per-feature selection).
- Retention policy.
- MCP server: enable/disable, per-tool toggles for write tools, token management.
- Global kill switch for actions.

### 2.5 Onboarding

- First-run wizard walks through each permission with clear why.
- Offers to install `amctl install-shim` and register MCP servers.

## 3. Architecture (app target)

- SwiftUI + `@Observable` (macOS 14+).
- `AppDependencies` composition root wires:
  - `ActivityStore` (GRDB)
  - `CaptureCoordinator`
  - `ActionRegistry`
  - `LLMProviderRegistry`
  - `IPCServer`
- Each view owns a `@State` view model that talks only to use cases / registries.
- No direct use-case-to-view coupling — all via injectable view models.

## 4. Permissions

- Info.plist entries: NSAppleEventsUsageDescription, NSCalendarsUsageDescription, NSUserNotificationsUsageDescription, NSFocusStatusUsageDescription, NSSystemAdministrationUsageDescription (if privileged helper later).
- Accessibility check via `AXIsProcessTrusted`.

## 5. Performance targets

- Menu-bar extra: first paint ≤ 150 ms after launch.
- Timeline window open: ≤ 250 ms first paint.
- Timeline scroll: 60 fps through a week of data.
- Memory steady-state: < 200 MB.

## 6. Testing strategy

- Unit tests per view model.
- Snapshot tests for key views (deferred — snapshot libs add dependency weight).
- UI smoke test via XCUITest: launch, open timeline, create rule in NL, verify rule shows in list.

## 7. Acceptance

- [ ] App launches, menu-bar extra appears, sends one event to store within 10 s.
- [ ] Timeline window renders today's sessions.
- [ ] Rule editor: NL → compiled DSL → rule persisted in dryRun state.
- [ ] Settings page honors toggles (actions off → kill action refused with "global kill switch").
- [ ] IPC server reachable from `amctl status`.

## 8. Out of scope

- Widget extension.
- Menu-bar extra plugins.
- Themes (inherit system).
