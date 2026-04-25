# Release Plan — v1.0

This document is the single source of truth for the v1.0.0 ship. It captures locked decisions, the feature inventory pointer, the cut sequence, and the readiness gates that must be green before tagging.

> **Feature inventory:** see [`docs/features.md`](docs/features.md) for the per-surface breakdown of what's in 1.0.0.
> **Architecture write-up:** [`docs/launch/architecture-post.md`](docs/launch/architecture-post.md).
> **User-facing notes:** the [`CHANGELOG.md`](CHANGELOG.md) `[1.0.0]` block is the published changelog body.

## Locked decisions

| Question | Decision | Rationale |
|---|---|---|
| Pricing | **Free, MIT-licensed, no Pro tier** | Open-source positions us as the developer-friendly alternative to RescueTime/Timing; cost barrier kills the "ask Claude to clean up my Mac" demo |
| Distribution | **Direct download — notarized DMG only** | App Store rejects MCP-style background helpers; direct DMG keeps us in control of release cadence and avoids a 30% dependency we don't need |
| Brand name | **"AI Activity Manager"** | Descriptive over clever — search-friendly, self-explanatory in HN/PH titles |
| Beta cohort | **Open from day one** | Open-source removes the gating reason for a closed beta; bug reports route through GitHub Issues |
| Telemetry | **None** | Privacy claim has to hold up to `tcpdump` on launch day |
| Auto-update | **Sparkle (post-1.0)** | Nice-to-have; v1.0 ships with a "check for updates" link to GitHub releases |

## v1.0 scope (ship list)

Product:
- [x] Frontmost-app + idle + focus capture → SQLite/FTS5 timeline (PRD-01..03)
- [x] `ProcessTerminator` with safety rails — per-bundle cooldown, SIP guard, unsaved-changes check (PRD-04)
- [x] Anthropic + Apple Foundation Models LLM providers; key in Keychain (PRD-05)
- [x] XPC IPC + typed client/server (PRD-06)
- [x] `amctl` CLI — full read/query/permissions/actions/rules/mcp surface (PRD-07)
- [x] `activity-mcp` MCP stdio server: 12 read tools + 4 write tools, audit log, per-client rate limit (PRD-08, PRD-10)
- [x] SwiftUI menu-bar shell with Overview / Processes / Timeline / Rules / Insights / Settings (PRD-09)
- [x] First-run walkthrough; Anthropic API key entry UI; Actions default off
- [x] `amctl mcp install` writes real configs for Claude Desktop / Cursor / Zed (JSON merge); `amctl mcp doctor` real diagnostics

Distribution:
- [x] Notarized DMG via `Scripts/build-release.sh --sign --dmg`
- [x] Homebrew tap (`homebrew/Formula/{amctl,activity-mcp}.rb`) — arch-split tarballs; SHA256s filled at release time
- [x] npm package (`@viveky/activity-mcp`) — `postinstall.js` downloads + SHA256-verifies the prebuilt binary
- [x] App icon, `Info.plist`, hardened-runtime entitlements

Quality gates:
- [x] CI: `swift test` matrix across every package on `macos-latest`
- [x] CI: SwiftLint `--strict` (zero violations across 153 files)
- [x] CI: Semgrep (OWASP/Swift/JS/secrets) + gitleaks
- [x] CI: release-build smoke (signed/notarized bundle layout asserts)
- [x] MCP server tool-response JSON snapshot regression
- [x] SwiftUI design-system image snapshot regression
- [x] `Scripts/mcp-inspect.sh` — interactive smoke target via official MCP Inspector
- [x] `Scripts/take-screenshots.sh` — AppleScript + AX-driven launch captures from the real app

Docs:
- [x] LICENSE (MIT), README, CHANGELOG, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY
- [x] `docs/features.md` (canonical inventory), `docs/launch/architecture-post.md` (MCP write-surface design)
- [x] `docs/launch/{show-hn, product-hunt, demo-script, press-blast, changelog-tweet}.md`

## v1.1+ deferred

- Sparkle auto-update
- Custom rules engine UI
- Multi-device timeline sync (privacy-preserving)
- Anthropic redactor v2 (beyond regex)
- Linux MCP-only build of `activity-mcp`

## Launch sequence (8 weeks)

| Week | Phase | Owner | Action |
|---|---|---|---|
| **−4** | Foundation | Maintainer | Lock 1.0 scope (this doc); cut v1.0.0 tag candidate; smoke-test notarized DMG on a clean macOS VM |
| **−3** | Soft launch | Maintainer | Push to GitHub public; share with ~10 trusted Mac/AI devs for feedback over GitHub Discussions |
| **−2** | Asset prep | Maintainer | Record 60-sec demo (script in `docs/launch/demo-script.md`); shoot 3 screenshots (Overview, MCP demo, Settings) |
| **−1** | Press warmup | Maintainer | Email MacStories, Daring Fireball, 9to5Mac under embargo (template in `docs/launch/press-blast.md`); DM creators in Cursor/Zed circles |
| **0**  | Launch day | Maintainer | Show HN post (`docs/launch/show-hn.md`), Product Hunt (`docs/launch/product-hunt.md`), r/macapps, r/ClaudeAI, X/LinkedIn threads |
| **+1** | Proof drop | Maintainer | "7 days with an AI activity manager" blog post; real numbers (memory reclaimed, tool calls served, audit log size) |
| **+2** | Use cases | Maintainer | Weekly blog: timeline recall, focus mode, Cursor integration |
| **+4** | v1.1 | Maintainer | Ship the #1 GitHub issue feature; "what we shipped in 30 days" recap |

## Channels

- **Owned** — `README.md`, GitHub Releases, GitHub Discussions, CHANGELOG.md
- **Earned** — Show HN, Product Hunt, MacStories, Indie Mac Apps, Latent Space podcast pitch
- **Communities** — r/macapps, r/ClaudeAI, r/cursor, MCP server directory, Anthropic Discord, Zed/Cursor Slack

## Success metrics (first 30 days)

| Metric | Target |
|---|---|
| GitHub stars | 1,000 |
| DMG downloads (HN traffic spike) | 5,000 |
| Active MCP installs (`mcp doctor` checks-in via opt-in ping if added later) | 500 |
| Inbound creator/journalist mentions | 25 |
| GitHub Issues filed | 50 (signal of real usage, not noise) |
| External contributors | 5 PRs merged from non-maintainer accounts |

## Risks

| Risk | Mitigation |
|---|---|
| Notarization rejected on launch day | Smoke-test on clean VM at week −4; keep an unsigned fallback DMG for early adopters who toggle Gatekeeper themselves |
| MCP host config schema changes (Claude Desktop/Cursor/Zed) | `amctl mcp install` writes via JSON merge, not overwrite — easy to patch |
| TCC permission UX confusion | Walkthrough covers it; "Open System Settings" buttons in Settings → Permissions |
| HN frontpage → Anthropic API rate limits | Default provider is `.null`; key entry is opt-in, so no shared rate-limit fan-out |

## Pre-tag readiness checklist

Run through this on the machine that will cut the release. Every item must be green before `git tag v1.0.0`.

- [ ] `git status` is clean; on `main`; pulled latest.
- [ ] `CHANGELOG.md` `[1.0.0]` block dated today; nothing left in `[Unreleased]`.
- [ ] `Resources/Info.plist` — `CFBundleShortVersionString` and `CFBundleVersion` both set to `1.0.0`.
- [ ] `swift test` passes for all four packages (commands below).
- [ ] `swiftlint lint --strict` returns zero violations.
- [ ] `Scripts/mcp-inspect.sh` boots the server and `tools/list` returns 16 tools (12 read + 4 write).
- [ ] `Scripts/take-screenshots.sh` produces all six PNGs under `docs/launch/assets/screenshots/`; eyeball each one.
- [ ] `Scripts/build-release.sh --sign --dmg` succeeds and the resulting DMG mounts on a clean macOS VM, drag-installs, opens, and walks through onboarding.
- [ ] `./build/release/ActivityManager.app/Contents/MacOS/amctl --help` runs from the bundled binary.
- [ ] `tcpdump`-spot-check the launched app — no network egress except when the user invokes an LLM with a saved Anthropic key.
- [ ] Homebrew formulae arch SHA256s replaced (procedure: `homebrew/README.md`).
- [ ] npm `postinstall.js` `CHECKSUMS` map updated with real arch SHA256s (no placeholder strings).

## Cutting the release

```bash
# 1. Final test pass
swift test --package-path Apps/ActivityManager
swift test --package-path Apps/amctl
swift test --package-path Packages/ActivityActions
swift test --package-path Packages/ActivityMCP

# 2. Bump version in Resources/Info.plist (CFBundleShortVersionString + CFBundleVersion)
#    and CHANGELOG.md (move [Unreleased] → [1.0.0] dated today).

# 3. Build signed + notarized DMG (sources secrets from ../../secrets/ai_activity_manager_macos/.env)
./Scripts/build-release.sh --sign --dmg

# 4. Compute checksums (publish alongside the DMG so installers can verify)
cd build/release
shasum -a 256 ActivityManager.dmg | tee ActivityManager.dmg.sha256
shasum -a 256 ActivityManager.zip | tee ActivityManager.zip.sha256
cd -

# 5. Tag and push
git tag v1.0.0 -m "v1.0.0"
git push origin v1.0.0

# 6. Create the GitHub Release (attaches DMG + zip + checksums; CHANGELOG excerpt as body)
gh release create v1.0.0 \
  build/release/ActivityManager.dmg \
  build/release/ActivityManager.dmg.sha256 \
  build/release/ActivityManager.zip \
  build/release/ActivityManager.zip.sha256 \
  --title "v1.0.0" \
  --notes-file <(awk '/^## \[1\.0\.0\]/{flag=1;next} /^## \[/{flag=0} flag' CHANGELOG.md)

# 7. Update Sparkle appcast (when Sparkle ships post-1.0)
#    Resources/appcast.xml — bump <enclosure url> + <sparkle:version>
```
