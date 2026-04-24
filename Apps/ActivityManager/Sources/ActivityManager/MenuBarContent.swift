import SwiftUI
import AppKit
import ActivityManagerCore

/// Glanceable menu-bar popover. Shows what the user is doing *right now* and
/// a single primary CTA to open the main window. Secondary action is Quit.
///
/// Design intent (HIG): one primary CTA per surface; title + live card +
/// action cluster; no truncation surprises thanks to fixed 280pt width.
struct MenuBarContent: View {
    let deps: AppDependencies

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            header
            activityCard
            actions
        }
        .padding(DS.Space.md)
        .frame(width: 280)
        .task { await deps.bootstrap() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 26, height: 26)
                .background(DS.Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("ActivityManager")
                    .font(.headline)
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusSubtitle: String {
        if deps.current.isIdle { return "Idle" }
        if deps.current.bundleID != nil { return "Live" }
        return "Waiting for first event…"
    }

    // MARK: - Activity card

    private var activityCard: some View {
        DSCard(padding: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: deps.current.isIdle ? "moon.zzz" : "app.badge")
                        .font(.title3)
                        .foregroundStyle(deps.current.isIdle ? DS.Palette.warning : DS.Palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .textCase(.uppercase)
                        Text(deps.current.display)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }

                if let bid = deps.current.bundleID, !bid.isEmpty {
                    Text(bid)
                        .font(.caption2.monospaced())
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: DS.Space.xs) {
                    DSPill(
                        "\(deps.current.sampleCount) events",
                        symbol: "bolt.fill",
                        kind: deps.current.sampleCount == 0 ? .neutral : .info
                    )
                    if let ts = deps.current.lastChangeAt {
                        DSPill(relativeTime(ts), symbol: "clock", kind: .neutral)
                    }
                }
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: DS.Space.xs) {
            Button {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                HStack {
                    Image(systemName: "macwindow")
                    Text("Open Main Window")
                    Spacer()
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .dsPrimaryButtonStyle()
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: [.command])
            .accessibilityLabel("Open ActivityManager main window")

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("Quit ActivityManager")
                    Spacer()
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
