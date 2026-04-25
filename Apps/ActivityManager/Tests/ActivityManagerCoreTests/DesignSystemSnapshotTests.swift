#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
import SnapshotTesting
@testable import ActivityManagerCore

/// Image-snapshot regression gate for the reusable SwiftUI primitives that
/// every screen composes (`DSCard`, `DSPill`, `DSEmptyState`, `DSStat`,
/// `DSSectionHeader`). A pixel diff here surfaces accidental palette /
/// spacing / radius regressions before they ship.
///
/// Scope note: the screen-level views (`MainWindow`, `SidebarView`, etc.)
/// live in the `ActivityManager` executable target, which a SwiftPM test
/// target cannot import. Broader screen-level snapshotting requires
/// extracting those views into `ActivityManagerCore` first — tracked as a
/// follow-up. For now we pin the design-system primitives, which is where
/// regressions are most expensive and most likely.
@Suite("DesignSystem image snapshots")
@MainActor
struct DesignSystemSnapshotTests {
    private func render<V: View>(_ view: V, size: CGSize) -> NSImage {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    @Test("DSCard renders with stable padding / radius")
    func dsCardSnapshot() {
        let view = DSCard {
            Text("Hello, world").font(.headline)
        }
        .padding(DS.Space.lg)
        .frame(width: 320)

        assertSnapshot(of: render(view, size: CGSize(width: 320, height: 120)), as: .image)
    }

    @Test("DSPill renders all kinds")
    func dsPillKindsSnapshot() {
        let view = HStack(spacing: DS.Space.sm) {
            DSPill("Neutral", symbol: "circle", kind: .neutral)
            DSPill("OK", symbol: "checkmark.circle.fill", kind: .success)
            DSPill("Warn", symbol: "exclamationmark.triangle.fill", kind: .warning)
            DSPill("Bad", symbol: "xmark.octagon.fill", kind: .danger)
            DSPill("Info", symbol: "info.circle.fill", kind: .info)
        }
        .padding(DS.Space.md)

        assertSnapshot(of: render(view, size: CGSize(width: 540, height: 60)), as: .image)
    }

    @Test("DSEmptyState renders title + message")
    func dsEmptyStateSnapshot() {
        let view = DSEmptyState(
            symbol: "tray",
            title: "Nothing to see yet",
            message: "Connect Activity Manager to your MCP host to start capturing."
        )
        .frame(width: 480, height: 240)

        assertSnapshot(of: render(view, size: CGSize(width: 480, height: 240)), as: .image)
    }

    @Test("DSStat renders aligned label/value rows")
    func dsStatSnapshot() {
        let view = VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSStat("Captured events", value: "12,345", symbol: "tray.full")
            DSStat("Active sources", value: "2", symbol: "dot.radiowaves.left.and.right")
            DSStat("Actions enabled", value: "off", symbol: "lock.fill")
        }
        .padding(DS.Space.lg)

        assertSnapshot(of: render(view, size: CGSize(width: 360, height: 160)), as: .image)
    }

    @Test("DSSectionHeader renders title + subtitle + accessory")
    func dsSectionHeaderSnapshot() {
        let view = DSSectionHeader(
            "Recent activity",
            subtitle: "Last 30 minutes"
        ) {
            DSPill("12", symbol: "bell", kind: .info)
        }
        .padding(DS.Space.lg)

        assertSnapshot(of: render(view, size: CGSize(width: 480, height: 80)), as: .image)
    }
}
#endif
