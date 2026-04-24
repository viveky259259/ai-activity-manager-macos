import Foundation
import ActivityCore

/// ``LLMProvider`` backed by the Anthropic Messages API.
///
/// The provider is deliberately transport-agnostic: callers inject a
/// ``URLSession`` (tests substitute one backed by a ``URLProtocol`` stub), and
/// the API key is supplied as a plain string — Keychain integration lives a
/// layer above this type.
///
/// On HTTP 429 the provider performs exactly one retry, honoring the
/// `Retry-After` header (capped at 30 seconds) if present. Any subsequent 429
/// surfaces as ``LLMError/rateLimited(retryAfter:)``.
public final class AnthropicProvider: LLMProvider, @unchecked Sendable {

    public let identifier: String
    public let isLocal: Bool = false

    private let apiKey: String
    private let model: String
    private let endpoint: URL
    private let session: URLSession
    private let anthropicVersion: String
    private let maxRetryDelay: TimeInterval

    public init(
        apiKey: String,
        model: String = "claude-opus-4-7",
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        anthropicVersion: String = "2023-06-01",
        maxRetryDelay: TimeInterval = 30
    ) {
        self.apiKey = apiKey
        self.model = model
        self.identifier = "anthropic:\(model)"
        self.session = session
        self.endpoint = endpoint
        self.anthropicVersion = anthropicVersion
        self.maxRetryDelay = maxRetryDelay
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let urlRequest = try makeURLRequest(for: request)
        do {
            return try await send(urlRequest, allowRetry: true)
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.transport(String(describing: error))
        }
    }

    // MARK: - Request construction

    private func makeURLRequest(for request: LLMRequest) throws -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = RequestBody(
            model: model,
            max_tokens: request.maxTokens,
            temperature: request.temperature,
            system: request.system,
            messages: [
                RequestBody.Message(role: "user", content: request.user)
            ]
        )
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    // MARK: - Transport

    private func send(_ request: URLRequest, allowRetry: Bool) async throws -> LLMResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.transport("Non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300:
            return try parse(data: data)
        case 401:
            throw LLMError.authenticationFailed
        case 429:
            let retryAfter = parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"))
            if allowRetry {
                if let retryAfter, retryAfter > 0 {
                    let delay = min(retryAfter, maxRetryDelay)
                    try await sleep(seconds: delay)
                }
                return try await send(request, allowRetry: false)
            }
            throw LLMError.rateLimited(retryAfter: retryAfter)
        default:
            throw LLMError.transport(String(http.statusCode))
        }
    }

    private func parse(data: Data) throws -> LLMResponse {
        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            let text = decoded.content
                .filter { $0.type == "text" }
                .compactMap { $0.text }
                .joined()
            return LLMResponse(
                text: text,
                inputTokens: decoded.usage?.input_tokens ?? 0,
                outputTokens: decoded.usage?.output_tokens ?? 0,
                model: decoded.model ?? model
            )
        } catch {
            throw LLMError.invalidResponse(String(describing: error))
        }
    }

    private func parseRetryAfter(_ header: String?) -> TimeInterval? {
        guard let header else { return nil }
        if let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)) {
            return seconds
        }
        // Anthropic may return an HTTP-date; parse it and diff against now.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: header) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    private func sleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        let nanos = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
    }
}

// MARK: - Wire format

private struct RequestBody: Encodable {
    let model: String
    let max_tokens: Int
    let temperature: Double
    let system: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ResponseBody: Decodable {
    let content: [ContentBlock]
    let usage: Usage?
    let model: String?

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
    }
}
