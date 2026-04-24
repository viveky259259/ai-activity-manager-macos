import Foundation
import Testing
import ActivityCore
import ActivityCoreTestSupport
@testable import ActivityLLM

@Suite("DefaultLLMProviderRegistry")
struct DefaultLLMProviderRegistryTests {

    @Test("returns mapped provider when feature is registered")
    func mappedReturned() {
        let fallback = FakeLLMProvider(identifier: "fallback")
        let compiler = FakeLLMProvider(identifier: "compiler")
        let recall = FakeLLMProvider(identifier: "recall")

        let registry = DefaultLLMProviderRegistry(
            providers: [
                .ruleCompilation: compiler,
                .recallAnswering: recall,
            ],
            default: fallback
        )

        #expect(registry.provider(for: .ruleCompilation).identifier == "compiler")
        #expect(registry.provider(for: .recallAnswering).identifier == "recall")
    }

    @Test("returns default when feature is not registered")
    func defaultUsedWhenMissing() {
        let fallback = FakeLLMProvider(identifier: "fallback")
        let registry = DefaultLLMProviderRegistry(providers: [:], default: fallback)
        #expect(registry.provider(for: .classification).identifier == "fallback")
        #expect(registry.provider(for: .summarization).identifier == "fallback")
    }

    @Test("register / unregister mutate the mapping")
    func registerUnregister() {
        let fallback = FakeLLMProvider(identifier: "fallback")
        let summarizer = FakeLLMProvider(identifier: "summarizer")
        let registry = DefaultLLMProviderRegistry(default: fallback)

        #expect(registry.provider(for: .summarization).identifier == "fallback")
        registry.register(summarizer, for: .summarization)
        #expect(registry.provider(for: .summarization).identifier == "summarizer")
        registry.unregister(.summarization)
        #expect(registry.provider(for: .summarization).identifier == "fallback")
    }

    @Test("setDefault replaces the fallback")
    func setDefault() {
        let original = FakeLLMProvider(identifier: "orig")
        let replacement = FakeLLMProvider(identifier: "replacement")
        let registry = DefaultLLMProviderRegistry(default: original)
        #expect(registry.provider(for: .classification).identifier == "orig")
        registry.setDefault(replacement)
        #expect(registry.provider(for: .classification).identifier == "replacement")
    }

    @Test("concurrent access: many simultaneous readers and writers are safe")
    func concurrentAccessIsSafe() async {
        let fallback = FakeLLMProvider(identifier: "fallback")
        let a = FakeLLMProvider(identifier: "a")
        let b = FakeLLMProvider(identifier: "b")
        let registry = DefaultLLMProviderRegistry(default: fallback)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    if index % 3 == 0 {
                        registry.register(a, for: .ruleCompilation)
                    } else if index % 3 == 1 {
                        registry.register(b, for: .recallAnswering)
                    } else {
                        _ = registry.provider(for: .classification)
                    }
                }
            }
        }

        // Final state: ruleCompilation and recallAnswering are mapped, others
        // fall through to the default. The precise winner doesn't matter for
        // race-freedom; only that no crash / data race occurred and the
        // mappings are consistent.
        let rc = registry.provider(for: .ruleCompilation).identifier
        let ra = registry.provider(for: .recallAnswering).identifier
        let cls = registry.provider(for: .classification).identifier
        #expect(rc == "a")
        #expect(ra == "b")
        #expect(cls == "fallback")
    }
}
