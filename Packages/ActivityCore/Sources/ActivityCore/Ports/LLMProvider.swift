import Foundation

public protocol LLMProvider: Sendable {
    var identifier: String { get }
    var isLocal: Bool { get }
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}

public struct LLMRequest: Hashable, Sendable, Codable {
    public var system: String
    public var user: String
    public var maxTokens: Int
    public var temperature: Double
    public var responseFormat: ResponseFormat

    public init(
        system: String,
        user: String,
        maxTokens: Int = 1024,
        temperature: Double = 0.2,
        responseFormat: ResponseFormat = .text
    ) {
        self.system = system
        self.user = user
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.responseFormat = responseFormat
    }

    public enum ResponseFormat: Hashable, Sendable, Codable {
        case text
        case json(schema: String?)
    }
}

public struct LLMResponse: Hashable, Sendable, Codable {
    public var text: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var model: String

    public init(text: String, inputTokens: Int, outputTokens: Int, model: String) {
        self.text = text
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.model = model
    }
}

public enum LLMError: Error, Sendable, Equatable {
    case unavailable
    case rateLimited(retryAfter: TimeInterval?)
    case invalidResponse(String)
    case transport(String)
    case authenticationFailed
}

public enum LLMFeature: String, Sendable, Codable, CaseIterable {
    case ruleCompilation
    case recallAnswering
    case classification
    case summarization
}

public protocol LLMProviderRegistry: Sendable {
    func provider(for feature: LLMFeature) -> LLMProvider
}
