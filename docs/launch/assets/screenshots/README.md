# Screenshots

These five PNGs are referenced from the root `README.md`, the Product Hunt gallery (`docs/launch/product-hunt.md`), and the press kit (`docs/launch/press-blast.md`). Capture them before tagging v1.0.0.

| File | What it shows | Notes |
|---|---|---|
| `01-overview.png` | Menu-bar popover open. Process list, total memory, last 30 min of timeline. Cursor on the Overview tab. | The "hero" image. Used in README header. |
| `02-mcp-claude-desktop.png` | Claude Desktop conversation: *"list my heaviest idle apps"* → tool call expanded → 3 results. | Shows MCP working end-to-end. |
| `03-mcp-cursor.png` | Cursor with the same MCP wiring — proves "any MCP host" claim. | |
| `04-settings-permissions.png` | Settings → Permissions tab. All three permission rows visible with status badges. **Actions enabled** toggle visible and OFF. | Surfaces the safety-rail story. |
| `05-timeline-search.png` | Timeline tab with a search query active and filter pills. | |

## Capture conventions

- 1920×1080, retina (`@2x`)
- Dark mode, Solid Color #1B1B1F desktop
- Hide the rest of the menu bar (Bartender / Hidden Bar)
- Quit Slack, Mail, Messages before capturing
- Use the demo-user account (clean of personal data)

## Automation

`./Scripts/take-screenshots.sh` drives the running app via AppleScript and
writes one PNG per sidebar section into this directory. It assumes:

- `ActivityManager.app` is installed at `/Applications/` (override with
  `APP_PATH=/path/to/ActivityManager.app`).
- The shell that runs the script has Accessibility permission (System
  Settings → Privacy & Security → Accessibility).

The script captures real data from your live timeline; review each PNG before
committing. Re-run any time — files are overwritten.
