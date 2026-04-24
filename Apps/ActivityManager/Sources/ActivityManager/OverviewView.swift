import SwiftUI
import ActivityCore
import ActivityManagerCore

/// Home / dashboard surface. Summarises what the user is doing *now*, what
/// they've been doing in the last hour, and exposes quick links to the deeper
/// surfaces. One primary CTA per card per HIG.
struct OverviewView: View {
    let deps: AppDependencies
    @State private var viewModel: TimelineViewModel
    @Binding var selection: Section

    init(deps: AppDependencies, selection: Binding<Section>) {
        self.deps = deps
        self._selection = selection
        _viewModel = State(initialValue: TimelineViewModel(store: deps.store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                DSSectionHeader(
                    "Overview",
                    subtitle: "Your live activity, recent sessions, and shortcuts."
                )

                heroCard
                statsRow
                recentSection
                shortcutsSection
            }
            .padding(DS.Space.lg)
        }
        .dsAmbientBackground()
        .task { await reload() }
    }

    // MARK: - Hero current activity

    private var heroCard: some View {
        DSCard(padding: DS.Space.lg) {
            HStack(alignment: .top, spacing: DS.Space.lg) {
                Image(systemName: deps.current.isIdle ? "moon.zzz.fill" : "app.badge.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(deps.current.isIdle ? DS.Palette.warning : DS.Palette.accent)
                    .frame(width: 56, height: 56)
                    .background(
                        (deps.current.isIdle ? DS.Palette.warning : DS.Palette.accent).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Current activity")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .textCase(.uppercase)
                    Text(deps.current.display)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: DS.Space.xs) {
                        if let bid = deps.current.bundleID, !bid.isEmpty {
                            DSPill(bid, symbol: "shippingbox", kind: .neutral)
                        }
                        DSPill(
                            "\(deps.current.sampleCount) events",
                            symbol: "bolt.fill",
                            kind: deps.current.sampleCount == 0 ? .neutral : .info
                        )
                        if let ts = deps.current.lastChangeAt {
                            DSPill(relative(ts), symbol: "clock", kind: .neutral)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: DS.Space.md) {
            DSCard(padding: DS.Space.md) {
                statTile(
                    label: "Sessions",
                    value: "\(viewModel.sessions.count)",
                    symbol: "rectangle.stack.fill",
                    tint: DS.Palette.accent
                )
            }
            DSCard(padding: DS.Space.md) {
                statTile(
                    label: "Active time",
                    value: activeDurationText,
                    symbol: "stopwatch.fill",
                    tint: .blue
                )
            }
            DSCard(padding: DS.Space.md) {
                statTile(
                    label: "Idle spans",
                    value: "\(idleCount)",
                    symbol: "moon.zzz.fill",
                    tint: .orange
                )
            }
        }
    }

    private func statTile(label: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var idleCount: Int {
        viewModel.sessions.reduce(0) { acc, s in
            if case .idleSpan = s.subject { return acc + 1 }
            return acc
        }
    }

    private var activeSeconds: Int {
        Int(viewModel.sessions.reduce(0.0) { acc, s in
            if case .idleSpan = s.subject { return acc }
            return acc + s.duration
        })
    }

    private var activeDurationText: String {
        let s = activeSeconds
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    // MARK: - Recent activity

    private var recentSection: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                DSSectionHeader("Last hour", subtitle: nil) {
                    Button {
                        selection = .timeline
                    } label: {
                        Label("Open timeline", systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .font(.body)

                Divider()

                if viewModel.isLoading {
                    HStack(spacing: DS.Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Loading…")
                            .font(.callout)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    .padding(.vertical, DS.Space.md)
                } else if viewModel.sessions.isEmpty {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text("No sessions yet. Switch between apps and they'll appear here.")
                            .font(.callout)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    .padding(.vertical, DS.Space.md)
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.sessions.prefix(6)) { session in
                            RecentRow(session: session)
                            if session.id != viewModel.sessions.prefix(6).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shortcuts

    private var shortcutsSection: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Shortcuts")
                    .font(.headline)
                Divider()
                HStack(spacing: DS.Space.sm) {
                    shortcutButton(
                        section: .processes,
                        label: "Processes",
                        symbol: "cpu",
                        tint: .blue
                    )
                    shortcutButton(
                        section: .rules,
                        label: "New rule",
                        symbol: "slider.horizontal.3",
                        tint: .teal
                    )
                    shortcutButton(
                        section: .insights,
                        label: "Ask",
                        symbol: "sparkles",
                        tint: .pink
                    )
                    shortcutButton(
                        section: .settings,
                        label: "Settings",
                        symbol: "gear",
                        tint: .gray
                    )
                }
            }
        }
    }

    private func shortcutButton(section: Section, label: String, symbol: String, tint: Color) -> some View {
        Button {
            selection = section
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                Text(label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(DS.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(label)")
    }

    // MARK: - Data

    private func reload() async {
        let now = Date()
        await viewModel.load(from: now.addingTimeInterval(-60 * 60), to: now)
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

private struct RecentRow: View {
    let session: ActivitySession

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(Self.timeFormatter.string(from: session.startedAt)) · \(durationText)")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            Spacer()
            Text("×\(session.sampleCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .padding(.vertical, DS.Space.xs)
    }

    private var durationText: String {
        let s = Int(session.duration)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }

    private var title: String {
        switch session.subject {
        case .app(_, let name):            return name.isEmpty ? "Unknown app" : name
        case .url(let host, _):            return host
        case .calendarEvent(_, let title): return title
        case .idleSpan:                    return "Idle"
        case .focusMode(let name):         return "Focus: \(name ?? "—")"
        case .screenshotText(let snip):    return "OCR: \(snip)"
        case .ruleFired(_, let name):      return "Rule fired: \(name)"
        case .custom(let kind, let id):    return "\(kind): \(id)"
        }
    }

    private var symbol: String {
        switch session.subject {
        case .app:           return "app.badge"
        case .url:           return "network"
        case .calendarEvent: return "calendar"
        case .idleSpan:      return "moon.zzz"
        case .focusMode:     return "moon.circle"
        case .screenshotText:return "text.viewfinder"
        case .ruleFired:     return "bolt.fill"
        case .custom:        return "ellipsis.circle"
        }
    }

    private var tint: Color {
        switch session.subject {
        case .app:           return .accentColor
        case .url:           return .blue
        case .calendarEvent: return .orange
        case .idleSpan:      return .gray
        case .focusMode:     return .indigo
        case .screenshotText:return .mint
        case .ruleFired:     return .pink
        case .custom:        return .secondary
        }
    }
}
