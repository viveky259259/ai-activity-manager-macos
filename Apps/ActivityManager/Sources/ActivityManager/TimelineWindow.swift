import SwiftUI
import ActivityCore
import ActivityManagerCore

struct TimelineView: View {
    let deps: AppDependencies
    @State private var viewModel: TimelineViewModel
    @State private var range: Range = .today

    enum Range: String, CaseIterable, Identifiable {
        case hour, today, week
        var id: String { rawValue }
        var label: String {
            switch self {
            case .hour:  return "Last hour"
            case .today: return "Today"
            case .week:  return "Last 7 days"
            }
        }
        var interval: TimeInterval {
            switch self {
            case .hour:  return 60 * 60
            case .today: return 60 * 60 * 24
            case .week:  return 60 * 60 * 24 * 7
            }
        }
    }

    init(deps: AppDependencies) {
        self.deps = deps
        _viewModel = State(initialValue: TimelineViewModel(store: deps.store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.lg)
                .padding(.bottom, DS.Space.md)

            Divider()

            content
        }
        .dsAmbientBackground()
        .task(id: range) { await reload() }
    }

    private var header: some View {
        DSSectionHeader(
            "Timeline",
            subtitle: "Collapsed activity sessions over time"
        ) {
            HStack(spacing: DS.Space.sm) {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)

                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                }

                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload sessions")
                .accessibilityLabel("Reload timeline")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = viewModel.errorMessage {
            DSEmptyState(
                symbol: "exclamationmark.triangle",
                title: "Couldn't load timeline",
                message: message
            )
        } else if viewModel.sessions.isEmpty && !viewModel.isLoading {
            DSEmptyState(
                symbol: "clock.arrow.circlepath",
                title: "No sessions yet",
                message: "Switch between apps or wait for idle events and they'll appear here."
            )
        } else {
            List(viewModel.sessions, id: \.id) { session in
                TimelineRow(session: session)
                    .listRowBackground(DS.Palette.windowBackground)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func reload() async {
        let now = Date()
        await viewModel.load(from: now.addingTimeInterval(-range.interval), to: now)
    }
}

private struct TimelineRow: View {
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
                .font(.title3)
                .foregroundStyle(symbolTint)
                .frame(width: 28, height: 28)
                .background(symbolTint.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text("\(Self.timeFormatter.string(from: session.startedAt)) · \(durationText) · \(session.sampleCount) samples")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
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

    private var symbolTint: Color {
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
