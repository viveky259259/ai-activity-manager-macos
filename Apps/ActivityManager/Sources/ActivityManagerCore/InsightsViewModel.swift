import Foundation
import ActivityCore

/// View-model for the Insights surface. Executes natural-language questions
/// against the recorded timeline via the `AnswerTimelineQuestion` use case.
///
/// If the configured LLM provider is the `NullLLMProvider` (identifier
/// `"null"`), the UI should show a disabled state rather than running the use
/// case — there's no model to answer with.
@MainActor
@Observable
public final class InsightsViewModel {
    public var question: String = ""
    public var isRunning: Bool = false
    public var answer: String = ""
    public var citedSessions: [ActivitySession] = []
    public var errorMessage: String?
    public var tookMillis: Int = 0

    /// Range the question is evaluated against.
    public enum Range: String, CaseIterable, Identifiable, Sendable {
        case lastHour, today, last7Days
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .lastHour:  return "Last hour"
            case .today:     return "Today"
            case .last7Days: return "Last 7 days"
            }
        }
        public var interval: TimeInterval {
            switch self {
            case .lastHour:  return 60 * 60
            case .today:     return 60 * 60 * 24
            case .last7Days: return 60 * 60 * 24 * 7
            }
        }
    }
    public var range: Range = .today

    private let store: any ActivityStore
    private let provider: LLMProvider
    private let redactor: Redactor
    private let clock: Clock

    public init(
        store: any ActivityStore,
        provider: LLMProvider,
        redactor: Redactor = PassthroughRedactor(),
        clock: Clock = SystemClock()
    ) {
        self.store = store
        self.provider = provider
        self.redactor = redactor
        self.clock = clock
    }

    /// `true` when the configured provider is the inert null fallback. The UI
    /// should disable the Ask button and show a hint steering the user to the
    /// LLM provider picker in Settings.
    public var isProviderNull: Bool {
        provider.identifier == "null"
    }

    public var providerIdentifier: String { provider.identifier }

    public func ask() async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isProviderNull else {
            errorMessage = "No LLM provider configured. Choose Anthropic or Local in Settings."
            return
        }

        isRunning = true
        errorMessage = nil
        answer = ""
        citedSessions = []
        defer { isRunning = false }

        let now = clock.now()
        let interval = DateInterval(start: now.addingTimeInterval(-range.interval), end: now)
        let useCase = AnswerTimelineQuestion(
            store: store,
            provider: provider,
            redactor: redactor,
            clock: clock
        )
        let input = AnswerTimelineQuestion.Input(question: trimmed, range: interval)

        do {
            let result = try await useCase.answer(input)
            self.answer = result.answer
            self.citedSessions = result.citedSessions
            self.tookMillis = result.tookMillis
        } catch {
            self.errorMessage = String(describing: error)
        }
    }
}
