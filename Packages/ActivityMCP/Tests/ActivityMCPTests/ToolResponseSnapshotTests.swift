import Foundation
import Testing
import SnapshotTesting
import ActivityCore
import ActivityIPC
@testable import ActivityMCP

/// Snapshot tests pin the exact JSON shape of each tool's response so changes
/// to field names, casing, or nesting can't slip past code review unnoticed.
///
/// Inputs are deterministic: a fixed `referenceDate` plus a hand-built event
/// stream. Tests do NOT call `current_context` / `recent_projects` with `Date()`
/// — they exercise the synchronous helpers (`aggregateRepoSpans`) and snapshot
/// pre-built tool args so wall-clock drift can't cause flakes.
@Suite("Tool response snapshots")
struct ToolResponseSnapshotTests {
    private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func renderJSON(_ value: JSONValue) -> String {
        let data = try? JSONEncoder.sorted.encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "<encode failed>"
    }

    private func tool(_ name: String, _ tools: [ToolDefinition]) throws -> ToolDefinition {
        try #require(tools.first(where: { $0.name == name }))
    }

    @Test("WindowTitleParser handles the canonical IDE title shapes")
    func parserCanonicalShapes() {
        let cases: [(bundle: String, title: String, repo: String?, file: String?)] = [
            ("com.todesktop.230313mzl4w4u92", "AuthService.swift — auth-service", "auth-service", "AuthService.swift"),
            ("com.microsoft.VSCode", "routes.ts - api-server - Visual Studio Code", "api-server", "routes.ts"),
            ("com.apple.dt.Xcode", "ai_activity_manager — ReadTools.swift", "ai_activity_manager", "ReadTools.swift"),
            ("dev.zed.Zed", "main.rs — engine-core", "engine-core", "main.rs"),
            ("com.jetbrains.intellij", "monolith – UserController.kt", "monolith", "UserController.kt"),
            ("com.apple.Terminal", "vivek@laptop: ~/code/auth-service", "auth-service", nil),
        ]
        for c in cases {
            let parsed = WindowTitleParser.parse(title: c.title, bundleID: c.bundle)
            #expect(parsed?.repo == c.repo)
            #expect(parsed?.file == c.file)
        }
    }

    @Test("aggregateRepoSpans groups deterministic events by repo")
    func aggregateRepoSpansSnapshot() {
        let base = Self.referenceDate
        let events = [
            event(.cursor, "Cursor", "auth.swift — auth-service", at: base),
            event(.cursor, "Cursor", "routes.swift — auth-service", at: base.addingTimeInterval(60)),
            event(.xcode, "Xcode", "widgetshop — Models.swift", at: base.addingTimeInterval(180)),
            event(.xcode, "Xcode", "widgetshop — Views.swift", at: base.addingTimeInterval(300)),
        ]
        let now = base.addingTimeInterval(420)
        let spans = ReadTools.aggregateRepoSpans(events: events, now: now)
            .sorted { $0.name < $1.name }

        let json: JSONValue = .array(spans.map { span in
            .object([
                "name": .string(span.name),
                "total_seconds": .int(Int(span.totalSeconds)),
                "files": .array(span.files.sorted().map { .string($0) }),
                "apps": .array(span.apps.sorted().map { .string($0) }),
            ])
        })
        assertSnapshot(of: renderJSON(json), as: .lines)
    }

    @Test("current_activity response shape is stable")
    func currentActivitySnapshot() async throws {
        let client = FakeActivityClient()
        client.setStatus(StatusResponse(
            sources: ["frontmost", "idle"],
            capturedEventCount: 12_345,
            actionsEnabled: true,
            permissions: ["accessibility": "granted", "calendar": "denied"]
        ))

        let tool = try tool("current_activity", ReadTools.make(client: client))
        let result = try await tool.handler(.object([:]))
        assertSnapshot(of: renderJSON(result), as: .lines)
    }

    @Test("list_rules response shape is stable")
    func listRulesSnapshot() async throws {
        let client = FakeActivityClient()
        let rule = Rule(
            id: UUID(uuidString: "F0E1D2C3-B4A5-4968-8778-695A4B3C2D1E")!,
            name: "close-idle-music",
            nlSource: "when iTunes is idle 60m, close it",
            trigger: .idleEnded,
            condition: nil,
            actions: [.logMessage("hi")],
            mode: .active,
            confirm: .never,
            cooldown: 60,
            createdAt: Self.referenceDate,
            updatedAt: Self.referenceDate
        )
        client.setRules(RulesResponse(rules: [rule]))

        let tool = try tool("list_rules", ReadTools.make(client: client))
        let result = try await tool.handler(.object([:]))
        assertSnapshot(of: renderJSON(result), as: .lines)
    }

    // MARK: helpers

    private enum IDE: String {
        case cursor = "com.todesktop.230313mzl4w4u92"
        case xcode = "com.apple.dt.Xcode"
    }

    private func event(_ ide: IDE, _ name: String, _ title: String, at ts: Date) -> ActivityEvent {
        ActivityEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: ts,
            source: .frontmost,
            subject: .app(bundleID: ide.rawValue, name: name),
            attributes: ["windowTitle": title]
        )
    }
}

private extension JSONEncoder {
    /// Sorted-keys encoder for deterministic snapshot output.
    static let sorted: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()
}
