# Rule examples

Each `*.json` file is one rule. Copy the contents and paste into the **Rules**
tab of Activity Manager (top-right "Add rule" → "Paste JSON"), or drop the
file into `~/Library/Application Support/ActivityManager/rules/` and restart
the app.

| File | What it does | Confirm | Actions toggle required |
|---|---|---|---|
| [`auto-focus-when-slack-closed.json`](./auto-focus-when-slack-closed.json) | Enables macOS Focus when Slack stays closed for 5 min | once | Yes |
| [`youtube-30min-warn.json`](./youtube-30min-warn.json) | Sends a notification after 30 min of YouTube | never | No (notifications only) |
| [`itunes-idle-60min-notify.json`](./itunes-idle-60min-notify.json) | Tracks issue [#2](https://github.com/viveky259259/ai-activity-manager-macos/issues/2) — interactive notification with a Close action | once | No (read-only today; interactive close pending v1.1) |
| [`autoclose-cursor-when-idle.json`](./autoclose-cursor-when-idle.json) | Politely quits Cursor after 90 min idle (skips if unsaved files) | always | Yes |

## Rule shape (reference)

```jsonc
{
  "id": "stable-uuid-or-slug",
  "name": "Human-readable label",
  "trigger": { "type": "appFocused", "bundleID": "com.apple.Music", "for": 1800 },
  "action": { "type": "postNotification", "title": "...", "body": "..." },
  "confirm": "once",          // "never" | "once" | "always"
  "enabled": true
}
```

### Triggers

- `idleEntered` / `idleEnded` — system idle state crossings.
- `appFocused` — app brought to the foreground for at least `for` seconds.
- `appLostFocus` — app left the foreground.
- `appQuit` — app terminated.
- `windowTitleMatches` — current frontmost window title matches a regex.

### Actions

- `setFocusMode` — sets a macOS Focus filter (`name` optional; defaults to "Do Not Disturb").
- `killApp` — terminates an app by bundle ID. Requires Actions toggle ON.
- `launchApp` — opens an app by bundle ID.
- `postNotification` — UNNotification with title + body.
- `runShortcut` — runs a Shortcuts.app shortcut by name.
- `logMessage` — writes to the local audit log (no UI).

### Confirm policy

- `never` — fires silently. Use only for non-destructive actions.
- `once` — first execution prompts; remembers the answer.
- `always` — every execution prompts.

## Validation

Run `amctl rules validate examples/rules/*.json` from the repo root to
validate the schema before pasting into the GUI.
