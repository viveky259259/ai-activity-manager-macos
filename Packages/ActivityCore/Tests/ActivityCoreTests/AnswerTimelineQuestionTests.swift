import Testing
import Foundation
@testable import ActivityCore
import ActivityCoreTestSupport

@Suite("AnswerTimelineQuestion")
struct AnswerTimelineQuestionTests {

    @Test("No matching sessions returns canned answer without calling LLM")
    func noDataPath() async throws {
        let store = FakeStore()
        let llm = FakeLLMProvider()
        let clock = FakeClock()
        let uc = AnswerTimelineQuestion(
            store: store, provider: llm, redactor: PassthroughRedactor(), clock: clock
        )
        let range = DateInterval(start: Fixtures.epoch, duration: 3600)
        let answer = try await uc.answer(.init(question: "what did I do?", range: range))
        #expect(answer.citedSessions.isEmpty)
        #expect(llm.requestCount == 0)
        #expect(answer.answer.contains("No activity"))
    }

    @Test("LLM is called when sessions exist and request contains context")
    func llmCalledWithContext() async throws {
        let store = FakeStore()
        try await store.append([
            Fixtures.frontmost(bundleID: "com.apple.Xcode", name: "Xcode", at: 0),
            Fixtures.frontmost(bundleID: "com.apple.Xcode", name: "Xcode", at: 30),
        ])
        let llm = FakeLLMProvider()
        llm.stubText("You used Xcode for 30 seconds.")
        let uc = AnswerTimelineQuestion(
            store: store, provider: llm, redactor: PassthroughRedactor(), clock: FakeClock()
        )
        let range = DateInterval(start: Fixtures.epoch, duration: 3600)
        let answer = try await uc.answer(.init(question: "what did I use?", range: range))
        #expect(answer.citedSessions.count == 1)
        #expect(llm.requestCount == 1)
        let req = llm.capturedRequest
        #expect(req?.user.contains("Xcode") == true)
    }

    @Test("Redactor is applied to context")
    func redactorApplied() async throws {
        struct FixedRedactor: Redactor {
            func redact(_ text: String) -> String { text.replacingOccurrences(of: "Xcode", with: "[REDACTED]") }
            func redact(_ event: ActivityEvent) -> ActivityEvent { event }
        }
        let store = FakeStore()
        try await store.append([Fixtures.frontmost(bundleID: "com.apple.Xcode", name: "Xcode", at: 0)])
        let llm = FakeLLMProvider()
        llm.stubText("ok")
        let uc = AnswerTimelineQuestion(store: store, provider: llm, redactor: FixedRedactor(), clock: FakeClock())
        let range = DateInterval(start: Fixtures.epoch, duration: 3600)
        _ = try await uc.answer(.init(question: "q", range: range))
        #expect(llm.capturedRequest?.user.contains("Xcode") == false)
        #expect(llm.capturedRequest?.user.contains("[REDACTED]") == true)
    }

    @Test("Context is truncated to budget")
    func contextBudget() async throws {
        let store = FakeStore()
        for i in 0..<50 {
            try await store.append([
                Fixtures.frontmost(bundleID: "com.example.app\(i)", name: "App\(i)LongName", at: Double(i * 100))
            ])
        }
        let llm = FakeLLMProvider()
        llm.stubText("ok")
        let uc = AnswerTimelineQuestion(store: store, provider: llm, redactor: PassthroughRedactor(), clock: FakeClock())
        let range = DateInterval(start: Fixtures.epoch, duration: 100_000)
        _ = try await uc.answer(.init(question: "q", range: range, maxContextChars: 200))
        let user = llm.capturedRequest?.user ?? ""
        #expect(user.count < 500)
    }
}
