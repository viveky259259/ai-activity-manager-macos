# AI Activity Manager for macOS

Swift-native macOS app combining **natural-language automation** over activity signals (framing D) with **timeline recall / searchable memory** (framing E). For professionals.

MCP-first: an MCP stdio server (`activity-mcp`) exposes live timeline, rules, and process data so AI hosts (Claude Desktop, Cursor, Zed) can answer questions like "which unused entertainment apps are hogging memory right now?" and, with explicit opt-in, terminate them by bundle id or pid — all routed through the same `ProcessTerminator` safety rails used by rules.

## Repository layout

```
Packages/
  ActivityCore/        Domain + use cases + ports. Zero I/O. Fully unit-testable.
  ActivityStore/       GRDB (SQLite + FTS5) adapter.
  ActivityCapture/     macOS capture sources (NSWorkspace, AX, EventKit, Focus).
  ActivityActions/     ProcessTerminator, FocusController, NotificationPoster.
  ActivityLLM/         LLMProvider protocol + Anthropic + FoundationModels.
  ActivityIPC/         Named XPC service + typed client/server.
  ActivityMCP/         MCP protocol handlers on top of the IPC client.
Apps/
  ActivityManager/     SwiftUI menu-bar app. Wires everything.
  amctl/               Command-line tool.
  activity-mcp/        MCP stdio server.
docs/
  prds/                Per-package product requirement documents.
```

## Principles

- Clean Architecture: dependencies point inward.
- TDD: Red → Green → Refactor. Never merge without tests.
- Privacy-first: local capture is non-negotiable; cloud LLM opt-in per feature.
- Safety-first actions: dry-run by default; destructive actions require opt-in + confirmation.

## Requirements

- macOS 14+ (Sonoma) for FoundationModels; 13+ for SMAppService.
- Swift 6.0+.
- Xcode 16+.
