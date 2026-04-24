import SwiftUI
import ActivityCore
import ActivityManagerCore

/// Natural-language recall surface. Asks questions like "What was I doing this
/// afternoon?" and routes them through `AnswerTimelineQuestion`.
///
/// When the active LLM provider is the inert `NullLLMProvider`, this view
/// degrades to an explanatory empty state pointing the user at Settings.
struct InsightsView: View {
    let deps: AppDependencies
    @State private var viewModel: InsightsViewModel

    init(deps: AppDependencies) {
        self.deps = deps
        _viewModel = State(initialValue: InsightsViewModel(
            store: deps.store,
            provider: deps.llm.provider(for: .recallAnswering)
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                DSSectionHeader(
                    "Insights",
                    subtitle: "Ask natural-language questions about your recent activity."
                )

                if viewModel.isProviderNull {
                    providerMissingCard
                } else {
                    askCard
                    if !viewModel.answer.isEmpty {
                        answerCard
                    }
                    if let message = viewModel.errorMessage {
                        errorCard(message)
                    }
                    if !viewModel.citedSessions.isEmpty {
                        citationsCard
                    }
                }

                suggestionsCard
            }
            .padding(DS.Space.lg)
        }
        .dsAmbientBackground()
    }

    // MARK: - Provider missing

    private var providerMissingCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(DS.Palette.accent)
                    Text("No LLM provider configured")
                        .font(.headline)
                    Spacer()
                    DSPill("null", symbol: "circle.slash", kind: .warning)
                }
                Text("Insights need a language model. Choose Anthropic (cloud, with redaction) or Local (on-device Apple Foundation Models) in Settings → LLM provider.")
                    .font(.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Ask

    private var askCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack {
                    Text("Your question")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                    Picker("Range", selection: $viewModel.range) {
                        ForEach(InsightsViewModel.Range.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                    .labelsHidden()
                }

                TextField(
                    "e.g. What was I working on this morning?",
                    text: $viewModel.question,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Question about your activity")

                HStack(spacing: DS.Space.sm) {
                    Button {
                        Task { await viewModel.ask() }
                    } label: {
                        Label("Ask", systemImage: "sparkles")
                    }
                    .dsPrimaryButtonStyle()
                    .disabled(viewModel.isRunning
                              || viewModel.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if viewModel.isRunning {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    DSPill("via \(viewModel.providerIdentifier)", symbol: "cpu", kind: .info)
                }
            }
        }
    }

    // MARK: - Answer

    private var answerCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack {
                    Text("Answer")
                        .font(.headline)
                    Spacer()
                    if viewModel.tookMillis > 0 {
                        DSPill("\(viewModel.tookMillis) ms", symbol: "clock", kind: .neutral)
                    }
                    DSPill("\(viewModel.citedSessions.count) sessions", symbol: "rectangle.stack", kind: .info)
                }
                Divider()
                Text(viewModel.answer)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Citations

    private var citationsCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Cited sessions")
                    .font(.headline)
                Divider()
                ForEach(viewModel.citedSessions.prefix(8)) { session in
                    CitationRow(session: session)
                    if session.id != viewModel.citedSessions.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        DSCard {
            HStack(alignment: .top, spacing: DS.Space.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.Palette.danger)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
    }

    // MARK: - Suggestions

    private var suggestionsCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Try asking")
                    .font(.headline)
                Divider()
                VStack(spacing: DS.Space.xs) {
                    suggestion("Which apps did I spend the most time in today?")
                    suggestion("How much time was I idle in the last hour?")
                    suggestion("Summarise my last 7 days of activity.")
                }
            }
        }
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            viewModel.question = text
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "quote.bubble")
                    .foregroundStyle(DS.Palette.textSecondary)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.vertical, DS.Space.xs)
            .padding(.horizontal, DS.Space.sm)
            .background(DS.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProviderNull)
    }
}

private struct CitationRow: View {
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
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                Text("\(Self.timeFormatter.string(from: session.startedAt)) · \(durationText)")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            Spacer()
            Text("×\(session.sampleCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(DS.Palette.textTertiary)
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
}
