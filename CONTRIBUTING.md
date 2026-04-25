# Contributing

Thanks for taking the time to look at the code. This project follows a few rules that keep the surface coherent:

## Ground rules

1. **TDD.** Red → Green → Refactor. New behaviour ships with a test that fails first.
2. **Clean Architecture.** Dependencies point inward (domain → use case → adapter → app). Domain code (`Packages/ActivityCore`) stays I/O-free.
3. **Privacy is a contract.** Don't add code that exfiltrates capture data, telemetry, or crash logs without an explicit, off-by-default opt-in.
4. **Safety-first on actions.** Anything that terminates a process or changes Focus mode goes through `ProcessTerminator`/`FocusController` so the existing rails (cooldown, SIP, unsaved-changes, kill switch) apply.

## Project layout

```
Packages/   Domain + adapter SwiftPM packages (each with its own tests)
Apps/       Executable targets: ActivityManager (UI), activity-mcp (stdio server), amctl (CLI)
Scripts/    Release + icon generation
Resources/  Info.plist, entitlements, icon
docs/       PRDs and launch assets
```

## Running tests

```bash
swift test --package-path Packages/ActivityCore
swift test --package-path Packages/ActivityActions
swift test --package-path Packages/ActivityMCP
swift test --package-path Apps/ActivityManager
swift test --package-path Apps/amctl
```

CI runs the same matrix on every PR (see `.github/workflows/ci.yml`).

## Filing issues

- **Bug?** Use the bug template. Include macOS version, app version, and steps to reproduce.
- **Feature?** Use the feature template. Describe the user job-to-be-done, not the implementation.
- **Security?** Email the maintainer privately rather than opening a public issue.

## Submitting a PR

1. Fork → branch from `main`.
2. Keep the change focused. One PR = one logical change.
3. Add tests. PRs without tests for new behaviour will be asked to add them.
4. Update `CHANGELOG.md` under `## [Unreleased]`.
5. Run the full test matrix locally before opening the PR.
6. Be ready for review feedback — mostly about scope and matching existing patterns.

## Style

- Match the surrounding code. Don't reformat unrelated lines.
- No comments that explain *what* — names should already do that. Comments are for *why* (a non-obvious constraint, a workaround, a hidden invariant).
- No new dependencies without a discussion in an issue first.

## Code of Conduct

This project follows the [Contributor Covenant](./CODE_OF_CONDUCT.md). Be respectful or be elsewhere.
