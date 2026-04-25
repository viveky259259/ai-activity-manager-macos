# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-04-25

First public release.

### Added
- Frontmost-app and idle capture sources, written to a local SQLite/FTS5 store.
- Timeline view with session collapsing and full-text search.
- Rule editor with natural-language → structured rule pipeline.
- MCP stdio server (`activity-mcp`) exposing read tools (`status`, `list_processes`, `timeline`, `rules`) and a write tool (`kill_app`) gated by per-bundle cooldown, SIP guard, and unsaved-changes check.
- Per-client sliding-window rate limit on `tools/call` (60/min read, 10/min write) with full audit log.
- `amctl` CLI: `status`, `events`, `query`, `tail`, `top`, `timeline`, `permissions`, `actions`, `rules`, `mcp install/doctor/token rotate`.
- `amctl mcp install claude-desktop|cursor|zed` writes real configs (JSON merge — preserves unrelated keys).
- Anthropic + Apple Foundation Models LLM providers; key stored in macOS Keychain.
- First-run walkthrough (Welcome → Permissions → Optional API key → Actions opt-in).
- Settings: Anthropic API key entry, retention slider, provider picker, per-row "Open System Settings" deeplinks.
- App icon, `Info.plist`, hardened-runtime entitlements.
- `Scripts/build-release.sh` builds notarized DMG with `/Applications` symlink (gates codesign + notarization on `DEVELOPER_ID_APP` + `AC_PROFILE`).
- `Scripts/generate-icon.swift` renders the icon at all 10 standard sizes via Quartz + `iconutil`.

### Changed
- Destructive actions default **off** at the app composition root. The `ProcessTerminator` library default stays on for test convenience; `AppDependencies` constructs it with `actionsEnabled: false`. Settings still persists the user's choice.
- `AppDependencies` no longer force-tries the SQLite fallback — retries 3 unique temp paths and surfaces a meaningful error on total failure.

### Security
- Anthropic API key is read only from Keychain; never logged, never written to disk in plaintext.
- No telemetry, no crash reporting, no analytics calls.

### Known limitations
- v1.0 has no auto-update mechanism — check GitHub Releases for new versions.
- The `Insights` view requires either an on-device Foundation Models provider (macOS 26) or a saved Anthropic key.
- App icon is a programmatic placeholder; designed icon will land in v1.1.
