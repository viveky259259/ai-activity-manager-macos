import Foundation

public struct AnswerTimelineQuestion: Sendable {
    public struct Input: Sendable {
        public var question: String
        public var range: DateInterval
        public var maxContextChars: Int
        public init(question: String, range: DateInterval, maxContextChars: Int = 4000) {
            self.question = question
            self.range = range
            self.maxContextChars = maxContextChars
        }
    }

    private let store: ActivityStore
    private let provider: LLMProvider
    private let redactor: Redactor
    private let clock: Clock

    public init(store: ActivityStore, provider: LLMProvider, redactor: Redactor, clock: Clock) {
        self.store = store
        self.provider = provider
        self.redactor = redactor
        self.clock = clock
    }

    public func answer(_ input: Input) async throws -> QueryAnswer {
        let query = TimelineQuery(range: input.range, fullText: nil, limit: 500)
        let events = try await store.search(query)
        let collapser = SessionCollapser()
        let sessions = collapser.collapse(events, gapThreshold: 60)

        if sessions.isEmpty {
            return QueryAnswer(
                answer: "No activity was recorded in that time range.",
                citedSessions: [],
                provider: provider.identifier,
                tookMillis: 0
            )
        }

        let context = Self.buildContext(sessions: sessions, budget: input.maxContextChars, redactor: redactor)
        let system = Self.systemPrompt
        let user = "Question: \(input.question)\n\nActivity context:\n\(context)"
        let request = LLMRequest(system: system, user: user, maxTokens: 512, temperature: 0.2)
        let start = clock.now()
        let response = try await provider.complete(request)
        let elapsed = Int(clock.now().timeIntervalSince(start) * 1000)

        return QueryAnswer(
            answer: response.text,
            citedSessions: sessions,
            provider: provider.identifier,
            tookMillis: elapsed
        )
    }

    static let systemPrompt = """
    You are an assistant answering questions about a user's own macOS activity history.
    You will be given a list of activity sessions and a question. Answer using only the provided sessions.
    Cite specific session subjects and timestamps in your answer. If the sessions do not contain enough information, say so.
    """

    static func buildContext(sessions: [ActivitySession], budget: Int, redactor: Redactor) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var lines: [String] = []
        var used = 0
        for session in sessions {
            let subject = describeSubject(session.subject)
            let line = "[\(formatter.string(from: session.startedAt))..\(formatter.string(from: session.endedAt))] \(subject) x\(session.sampleCount)"
            let redacted = redactor.redact(line)
            if used + redacted.count > budget { break }
            lines.append(redacted)
            used += redacted.count + 1
        }
        return lines.joined(separator: "\n")
    }

    static func describeSubject(_ subject: ActivityEvent.Subject) -> String {
        switch subject {
        case .app(_, let name): return "app:\(name)"
        case .url(let host, let path): return "url:\(host)\(path)"
        case .calendarEvent(_, let title): return "calendar:\(title)"
        case .focusMode(let name): return "focus:\(name ?? "off")"
        case .idleSpan: return "idle"
        case .screenshotText(let snippet): return "ocr:\(snippet)"
        case .ruleFired(_, let name): return "rule:\(name)"
        case .custom(let kind, let id): return "\(kind):\(id)"
        }
    }
}
