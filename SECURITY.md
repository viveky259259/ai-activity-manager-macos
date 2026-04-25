# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 1.0.x | ✅ |
| < 1.0 | ❌ |

Only the latest minor of v1.x receives security fixes.

## Reporting a vulnerability

**Please do not file public GitHub Issues for security-relevant bugs.**

Email the maintainer directly: **viveky259259@gmail.com** with `[security]` in the subject. PGP fingerprint available on request.

What to include:

- The version (`About → version`, or `git rev-parse HEAD` if built from source)
- macOS version
- A description of the issue and the impact you believe it has
- Reproduction steps or a proof-of-concept (a private gist link is fine)

You'll get a first response within **72 hours**. If the issue is confirmed, expect a fix and a coordinated disclosure window of **30 days** before details are made public, or sooner if a fix ships first.

## Scope

In scope:

- Local privilege escalation via `ProcessTerminator`, `FocusController`, or the XPC helper
- Bypass of the per-bundle cooldown, SIP guard, unsaved-changes check, or kill switch
- Unauthorized read or write of MCP tool calls (rate-limit bypass, audit-log tampering)
- Anthropic API key exfiltration paths or Keychain misuse
- Capture-data leakage (timeline, window titles) outside the local SQLite store

Out of scope:

- Issues that require physical access to an unlocked Mac
- Issues that require the user to disable macOS Gatekeeper, hardened runtime, or TCC
- Social-engineering attacks against the maintainer

## Hall of fame

A list of researchers who have responsibly disclosed issues will be maintained here once anyone earns a spot.
