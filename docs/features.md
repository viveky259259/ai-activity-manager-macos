# Features — v1.0

Canonical inventory of what ships in v1.0.0. Grouped by surface area. Each line cites the package or doc that owns it so you can jump from "what" to "where it lives" in one hop.

## Capture & memory

| Feature | Where it lives |
|---|---|
| Frontmost-app sampler (bundle ID, name, window title) | `Packages/ActivityCapture` · `FrontmostSource` |
| Idle source (begin / end events around configurable threshold) | `Packages/ActivityCapture` · `IdleSource` |
| Focus-mode source (do-not-disturb / focus filter signals) | `Packages/ActivityCapture` · `FocusSource` |
| Local SQLite/FTS5 store with retention pruning | `Packages/ActivityStore` · PRD-02 |
| Window-title parser for IDE titles (Cursor, VSCode, Xcode, Zed, JetBrains, Terminal/iTerm) → `(repo, file)` | `Packages/ActivityMCP` · `WindowTitleParser` |
| No telemetry, no remote calls; all data stays on device | enforced by absence of network code; verifiable with `tcpdump` |

## Menu-bar app surface

| Surface | Highlights |
|---|---|
| **Overview** | Live process list, total memory, last-30-min timeline strip |
| **Processes** | Per-process CPU/memory; sortable; "kill" gated by Actions toggle |
| **Timeline** | Session-collapsed event list with full-text search and filter pills |
| **Rules** | Natural-language rule editor (NL → structured trigger/condition/actions) |
| **Insights** | LLM-summarized "what did I do this week" — Anthropic *or* Apple Foundation Models |
| **Settings** | Permissions, retention, provider, API key entry, Actions toggle |
| **Onboarding** | First-run walkthrough: Welcome → Permissions → optional API key → Actions opt-in |

PRD: `docs/prds/PRD-09-ActivityManager-app.md`. Design system primitives (`DSCard`, `DSPill`, `DSEmptyState`, `DSStat`, `DSSectionHeader`) are pinned by image-snapshot tests.

## MCP server (`activity-mcp`)

12 read tools + 4 write tools, all exposed over stdio JSON-RPC.

**Read (12)** — `status`, `list_processes`, `timeline`, `query_timeline`, `permissions_status`, `current_activity`, `list_rules`, `audit_log`, `recent_projects`, `time_per_repo`, `files_touched`, `current_context`.

**Write (4)** — `kill_app`, `create_rule`, `update_rule`, `delete_rule`. All four require the user-controlled Actions toggle.

Cross-cutting guarantees:

- Per-client sliding-window rate limits — 60/min read, 10/min write.
- Every `tools/call` lands in the local audit log (subject, args, result, timestamp).
- Per-bundle cooldown + SIP guard + unsaved-changes check on `kill_app`.
- Schemas published via `tools/list`; smoke-testable end-to-end with `./Scripts/mcp-inspect.sh` (launches the official MCP Inspector against a fresh release build).

PRD: `docs/prds/PRD-08-activity-mcp.md`, `docs/prds/PRD-10-MCP-ProcessManagement.md`. Architecture write-up: `docs/launch/architecture-post.md`.

## CLI (`amctl`)

| Command | What it does |
|---|---|
| `amctl status` | Snapshot of capture sources + counts |
| `amctl events` / `tail` | Stream raw events (one-shot or follow) |
| `amctl query <text>` | FTS5 search over the timeline |
| `amctl top` | Top apps/processes by capture frequency |
| `amctl timeline` | Session-collapsed timeline view |
| `amctl permissions` | Live TCC status for accessibility / automation / calendar |
| `amctl actions enable/disable/status` | Toggle the destructive-action gate from CLI |
| `amctl rules list/show` | Read-side rule inspection |
| `amctl mcp install <claude-desktop\|cursor\|zed>` | JSON-merge installer for each host's config |
| `amctl mcp doctor` | Real diagnostics (binary present, config wired, server boots) |
| `amctl mcp token rotate` | Rotate the MCP server's local auth token |

PRD: `docs/prds/PRD-07-amctl.md`.

## Distribution

| Channel | Status |
|---|---|
| Notarized DMG (direct download) | `Scripts/build-release.sh --sign --dmg` |
| Homebrew tap | `homebrew/Formula/{amctl,activity-mcp}.rb` — arch-split tarballs (arm64 + x86_64); SHA256s filled at release time per `homebrew/README.md` |
| npm | `@viveky/activity-mcp` — `postinstall.js` downloads the prebuilt binary from the GitHub release, SHA256-verifies, refuses placeholder hashes |
| Source build | `swift build --package-path Apps/ActivityManager -c release` |

## Privacy & safety

- **No network egress** by default. The Anthropic provider is opt-in; until a key is saved, the LLM provider is `.null`.
- **Anthropic key in Keychain** — never logged, never written to disk in plaintext.
- **Actions default off** at the app composition root. `AppDependencies` constructs `ProcessTerminator` with `actionsEnabled: false` even though the library default is `true` (kept on for test convenience).
- **No telemetry, no crash reporters, no analytics.** Verifiable by inspection — there is no networking code outside the Anthropic client.

## Testing & CI

| Gate | Where |
|---|---|
| Swift Testing unit + integration suites | every `Packages/*` and `Apps/*` directory |
| MCP server tool-response JSON snapshot regression | `Packages/ActivityMCP/Tests/.../ToolResponseSnapshotTests.swift` |
| SwiftUI design-system image snapshot regression | `Apps/ActivityManager/Tests/.../DesignSystemSnapshotTests.swift` |
| MCP Inspector smoke (interactive) | `Scripts/mcp-inspect.sh` |
| Real-app launch screenshots (AppleScript + AX) | `Scripts/take-screenshots.sh` |
| `swiftlint --strict` lint gate | `.swiftlint.yml` + GitHub Actions `lint` job |
| Semgrep (OWASP/Swift/JS/secrets) | GitHub Actions `security` job |
| gitleaks (committed-secret scan) | GitHub Actions `security` job |
| Notarized release-build smoke | GitHub Actions `release-build` job |

Workflow: `.github/workflows/ci.yml`.

## Deferred to v1.1+

- Sparkle auto-update (1.0 ships with a "check for updates" link only).
- Custom rules-engine UI (the editor exists; the visual designer doesn't).
- Multi-device timeline sync (privacy-preserving, design TBD).
- Anthropic redactor v2 — beyond the regex pass.
- Linux MCP-only build of `activity-mcp`.
- Designed app icon (1.0 ships the programmatic placeholder).
- Screen-level SwiftUI snapshot coverage (requires lifting `MainWindow` / `SidebarView` / etc. out of the executable target into `ActivityManagerCore`).
