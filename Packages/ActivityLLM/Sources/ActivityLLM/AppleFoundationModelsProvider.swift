import Foundation
import ActivityCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device Apple Intelligence LLM provider.
///
/// Wraps `FoundationModels.LanguageModelSession` so the rest of the app can
/// treat it as a regular ``LLMProvider``. Runs fully on-device — no network,
/// no API key, no token costs.
///
/// Availability: requires macOS 26.0+ **and** a device with Apple Intelligence
/// enabled. When the model is not ready (e.g. still downloading) or the device
/// is ineligible, ``complete(_:)`` throws ``LLMError/unavailable``.
///
/// Rationale for the `@available(macOS 26.0, *)` gate rather than a package
/// platform bump: the ``ActivityLLM`` library still targets macOS 13 for
/// compatibility with Linux CI and older hosts. Callers on pre-26 systems
/// simply won't construct this type.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
public final class AppleFoundationModelsProvider: LLMProvider, @unchecked Sendable {
    public let identifier: String
    public let isLocal: Bool = true

    public init(identifierSuffix: String = "default") {
        self.identifier = "apple-foundation:\(identifierSuffix)"
    }

    /// `true` when the on-device model is ready to answer.
    public var isAvailable: Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    /// Reason the model is not available, if any. Surfaced in Settings so the
    /// user knows whether to enable Apple Intelligence or wait for the model
    /// to finish downloading.
    public var unavailableReason: String? {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Device is not eligible for Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is not enabled in System Settings."
            case .modelNotReady:
                return "Apple Intelligence model is downloading. Try again soon."
            @unknown default:
                return "Apple Intelligence is unavailable."
            }
        }
        #else
        return "FoundationModels framework is not available on this platform."
        #endif
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else {
            throw LLMError.unavailable
        }

        let session = LanguageModelSession(instructions: request.system)
        let options = GenerationOptions(
            temperature: request.temperature,
            maximumResponseTokens: request.maxTokens
        )

        do {
            let response = try await session.respond(to: request.user, options: options)
            return LLMResponse(
                text: response.content,
                inputTokens: 0, // FoundationModels does not expose token accounting.
                outputTokens: 0,
                model: identifier
            )
        } catch {
            throw LLMError.invalidResponse(String(describing: error))
        }
        #else
        throw LLMError.unavailable
        #endif
    }
}
