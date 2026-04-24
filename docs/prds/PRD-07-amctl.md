# PRD-07 — amctl (CLI)

**Status:** proposed · **Depends on:** PRD-06 · **Blocks:** none

## 1. Purpose

Command-line interface to the Activity Manager. Thin client over `ActivityIPC`. All commands compose with Unix pipes.

## 2. Dependencies

- [`swift-argument-parser`](https://github.com/apple/swift-argument-parser) ≥ 1.3.0.
- `ActivityIPC` client.

## 3. Commands (MVP)

```
amctl status
amctl query "<question>"
amctl timeline --from <ISO8601> --to <ISO8601> [--app <bundle>] [--format human|json|ndjson]
amctl events [--app <bundle>] [--source <src>] [--limit N] [--format ...]
amctl top --by app|host [--since today|7d|30d]
amctl rules list [--format ...]
amctl rules add "<nl description>"
amctl rules show <id>
amctl rules enable|disable|delete <id>
amctl rules dry-run <id> --since <period>
amctl actions kill --bundle <id> [--force] [--yes]
amctl actions focus set "<mode>"
amctl tail [--source <src>]
amctl permissions check|open <name>
```

## 4. Output

- Human: clean tables, colors when `isatty(stdout)`; no color when piped.
- JSON: one object, stable schema, `schema_version` field.
- NDJSON: one event/record per line.
- Every response includes optional `--timing` to emit `Elapsed: N ms` to stderr.

## 5. Exit codes

- `0` ok
- `2` usage error (`ArgumentParser` default)
- `3` permission denied (TCC)
- `4` host unreachable (app not running)
- `5` action refused (save dialog, cooldown, confirm timeout)
- `6` not permitted (SIP, sandbox)

## 6. Auto-launch

If `IPCClient.status()` fails with "host unreachable":

- Read-only commands → open SQLite read-only at the known DB path; return best-effort result.
- Write commands → launch app via `NSWorkspace.openApplication` and retry once after 2 s; if still unreachable → exit 4.

## 7. Install helper

```
amctl install-shim [--path <dir>]   # default: $HOME/.local/bin
amctl mcp install claude-desktop
amctl mcp install cursor
amctl mcp token rotate
amctl mcp doctor
```

`install-shim` creates a symlink from the target dir to the `amctl` binary inside `ActivityManager.app/Contents/MacOS/amctl`.

## 8. Testing strategy

- `ArgumentParser` parse tests for each command (happy + error paths).
- `IPCClient` fake: assert each command issues the right IPC call with the right DTO.
- Golden-file tests for human-readable output.
- JSON output validated against JSONSchema files in `Tests/Resources/schemas/`.

## 9. Acceptance

- [ ] `amctl --help` lists all commands.
- [ ] Every command has a `--help` section with at least one example.
- [ ] Exit codes match the table above (tested via `XCTest` launching the binary).
- [ ] JSON output round-trips through `JSONDecoder` without error for all commands.
- [ ] Color output disabled when `NO_COLOR` env var set or stdout not a TTY.

## 10. Out of scope

- Interactive REPL.
- Shell completions (nice-to-have post-MVP).
