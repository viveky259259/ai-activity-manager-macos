import Foundation
import Testing
@testable import ActivityLLM
import ActivityCore

@Suite("AppleFoundationModelsProvider")
struct AppleFoundationModelsProviderTests {

    @Test("Identifier is namespaced and isLocal is true")
    func identifierShape() {
        guard #available(macOS 26.0, *) else { return }
        let provider = AppleFoundationModelsProvider()
        #expect(provider.identifier.hasPrefix("apple-foundation"))
        #expect(provider.isLocal == true)
    }

    @Test("Throws LLMError.unavailable when Apple Intelligence is unavailable")
    func reportsUnavailable() async throws {
        guard #available(macOS 26.0, *) else { return }
        let provider = AppleFoundationModelsProvider()
        guard provider.isAvailable == false else {
            // Host has Apple Intelligence — can't exercise the unavailable
            // branch here; the "responds" test covers the happy path.
            return
        }
        do {
            _ = try await provider.complete(
                LLMRequest(system: "You are helpful.", user: "Hi", maxTokens: 16)
            )
            Issue.record("Expected LLMError.unavailable, got success")
        } catch let error as LLMError {
            #expect(error == .unavailable)
        }
    }

    @Test("Responds to a short prompt on eligible hardware")
    func respondsWhenAvailable() async throws {
        guard #available(macOS 26.0, *) else { return }
        let provider = AppleFoundationModelsProvider()
        guard provider.isAvailable else { return } // Skip on unsupported hosts.
        let response = try await provider.complete(
            LLMRequest(
                system: "Answer in one short sentence.",
                user: "Say 'ok'.",
                maxTokens: 32,
                temperature: 0.0
            )
        )
        #expect(!response.text.isEmpty)
        #expect(response.model.hasPrefix("apple-foundation"))
    }
}
