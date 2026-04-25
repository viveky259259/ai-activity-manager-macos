import Foundation
import Testing
@testable import ActivityMCP

@Suite("WindowTitleParser")
struct WindowTitleParserTests {
    @Test("Cursor: file on the left, repo on the right")
    func cursor() {
        let p = WindowTitleParser.parse(
            title: "AuthService.swift — auth-service",
            bundleID: "com.todesktop.230313mzl4w4u92"
        )
        #expect(p?.repo == "auth-service")
        #expect(p?.file == "AuthService.swift")
    }

    @Test("VSCode: trailing app name is stripped")
    func vscode() {
        let p = WindowTitleParser.parse(
            title: "routes.ts - api-server - Visual Studio Code",
            bundleID: "com.microsoft.VSCode"
        )
        #expect(p?.repo == "api-server")
        #expect(p?.file == "routes.ts")
    }

    @Test("Xcode: project on the left, file on the right")
    func xcode() {
        let p = WindowTitleParser.parse(
            title: "ai_activity_manager — ReadTools.swift",
            bundleID: "com.apple.dt.Xcode"
        )
        #expect(p?.repo == "ai_activity_manager")
        #expect(p?.file == "ReadTools.swift")
    }

    @Test("Zed: same convention as Cursor")
    func zed() {
        let p = WindowTitleParser.parse(
            title: "main.rs — engine-core",
            bundleID: "dev.zed.Zed"
        )
        #expect(p?.repo == "engine-core")
        #expect(p?.file == "main.rs")
    }

    @Test("JetBrains: en-dash separator")
    func jetbrains() {
        let p = WindowTitleParser.parse(
            title: "monolith – UserController.kt",
            bundleID: "com.jetbrains.intellij"
        )
        #expect(p?.repo == "monolith")
        #expect(p?.file == "UserController.kt")
    }

    @Test("Terminal: last path component after colon is the repo")
    func terminal() {
        let p = WindowTitleParser.parse(
            title: "vivek@laptop: ~/Documents/Projects/auth-service",
            bundleID: "com.apple.Terminal"
        )
        #expect(p?.repo == "auth-service")
        #expect(p?.file == nil)
    }

    @Test("iTerm: works without colon prefix")
    func iterm() {
        let p = WindowTitleParser.parse(
            title: "~/code/widgetshop",
            bundleID: "com.googlecode.iterm2"
        )
        #expect(p?.repo == "widgetshop")
    }

    @Test("Single segment with no extension: treat as repo")
    func singleRepoSegment() {
        let p = WindowTitleParser.parse(
            title: "auth-service",
            bundleID: "com.apple.dt.Xcode"
        )
        #expect(p?.repo == "auth-service")
        #expect(p?.file == nil)
    }

    @Test("Non-IDE bundle returns nil")
    func nonIDE() {
        let p = WindowTitleParser.parse(
            title: "Slack — #engineering",
            bundleID: "com.tinyspeck.slackmacgap"
        )
        #expect(p == nil)
    }

    @Test("nil bundleID returns nil")
    func missingBundleID() {
        #expect(WindowTitleParser.parse(title: "foo.swift — bar", bundleID: nil) == nil)
    }

    @Test("Empty title returns nil")
    func emptyTitle() {
        #expect(WindowTitleParser.parse(title: "   ", bundleID: "com.apple.dt.Xcode") == nil)
    }
}
