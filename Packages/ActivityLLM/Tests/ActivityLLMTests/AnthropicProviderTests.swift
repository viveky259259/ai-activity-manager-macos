import Foundation
import Testing
import os
import ActivityCore
@testable import ActivityLLM

@Suite("AnthropicProvider", .serialized)
struct AnthropicProviderTests {

    // MARK: - Happy path: request serialization

    @Test("request serialization: headers and body are correct")
    func happyPathRequestSerialization() async throws {
        let recorder = StubProtocol.Recorder()
        let response = try makeJSONResponse(
            status: 200,
            body: """
            {
              "content": [{"type":"text","text":"hello"}],
              "usage": {"input_tokens": 11, "output_tokens": 3},
              "model": "claude-opus-4-7"
            }
            """
        )
        StubProtocol.install(recorder: recorder, steps: [.respond(response)])
        defer { StubProtocol.reset() }

        let provider = AnthropicProvider(
            apiKey: "test-key",
            model: "claude-opus-4-7",
            session: Self.stubSession(),
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!
        )
        let result = try await provider.complete(
            LLMRequest(system: "sys", user: "hi", maxTokens: 64, temperature: 0.1)
        )

        #expect(result.text == "hello")
        #expect(result.inputTokens == 11)
        #expect(result.outputTokens == 3)
        #expect(result.model == "claude-opus-4-7")
        #expect(provider.identifier == "anthropic:claude-opus-4-7")
        #expect(provider.isLocal == false)

        let requests = recorder.allRequests()
        #expect(requests.count == 1)
        let req = try #require(requests.first)
        #expect(req.url == URL(string: "https://api.anthropic.com/v1/messages"))
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(req.value(forHTTPHeaderField: "content-type") == "application/json")

        let bodyData = try #require(req.bodyData)
        let json = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["model"] as? String == "claude-opus-4-7")
        #expect(json["max_tokens"] as? Int == 64)
        #expect((json["temperature"] as? Double).map { abs($0 - 0.1) < 1e-9 } == true)
        #expect(json["system"] as? String == "sys")
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages.first?["role"] as? String == "user")
        #expect(messages.first?["content"] as? String == "hi")
    }

    // MARK: - 429 retry

    @Test("429 with Retry-After triggers a single retry and returns success")
    func retryAfterTriggersOneRetry() async throws {
        let recorder = StubProtocol.Recorder()
        let first = try makeJSONResponse(status: 429, body: "{}", headers: ["Retry-After": "0"])
        let second = try makeJSONResponse(
            status: 200,
            body: """
            {
              "content": [{"type":"text","text":"ok"}],
              "usage": {"input_tokens": 1, "output_tokens": 1},
              "model": "claude-opus-4-7"
            }
            """
        )
        StubProtocol.install(recorder: recorder, steps: [.respond(first), .respond(second)])
        defer { StubProtocol.reset() }

        let provider = AnthropicProvider(
            apiKey: "key",
            session: Self.stubSession()
        )
        let result = try await provider.complete(
            LLMRequest(system: "s", user: "u")
        )

        #expect(result.text == "ok")
        #expect(recorder.allRequests().count == 2)
    }

    @Test("429 twice in a row surfaces rateLimited error")
    func twoConsecutive429sFail() async throws {
        let recorder = StubProtocol.Recorder()
        let resp429 = try makeJSONResponse(
            status: 429,
            body: "{}",
            headers: ["Retry-After": "0"]
        )
        StubProtocol.install(recorder: recorder, steps: [.respond(resp429), .respond(resp429)])
        defer { StubProtocol.reset() }

        let provider = AnthropicProvider(
            apiKey: "key",
            session: Self.stubSession()
        )
        do {
            _ = try await provider.complete(LLMRequest(system: "s", user: "u"))
            Issue.record("Expected to throw")
        } catch let LLMError.rateLimited(retryAfter) {
            #expect(retryAfter == 0 || retryAfter == nil)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(recorder.allRequests().count == 2)
    }

    // MARK: - 401 authentication

    @Test("401 surfaces authenticationFailed")
    func authFailure() async throws {
        let recorder = StubProtocol.Recorder()
        let resp = try makeJSONResponse(status: 401, body: "{}")
        StubProtocol.install(recorder: recorder, steps: [.respond(resp)])
        defer { StubProtocol.reset() }

        let provider = AnthropicProvider(
            apiKey: "bad",
            session: Self.stubSession()
        )
        do {
            _ = try await provider.complete(LLMRequest(system: "s", user: "u"))
            Issue.record("Expected to throw")
        } catch LLMError.authenticationFailed {
            // ok
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Malformed JSON

    @Test("malformed JSON body surfaces invalidResponse")
    func malformedJSON() async throws {
        let recorder = StubProtocol.Recorder()
        let resp = try makeJSONResponse(status: 200, body: "{ not json")
        StubProtocol.install(recorder: recorder, steps: [.respond(resp)])
        defer { StubProtocol.reset() }

        let provider = AnthropicProvider(
            apiKey: "k",
            session: Self.stubSession()
        )
        do {
            _ = try await provider.complete(LLMRequest(system: "s", user: "u"))
            Issue.record("Expected to throw")
        } catch let LLMError.invalidResponse(msg) {
            #expect(!msg.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - 5xx

    @Test("500 surfaces transport error with code")
    func serverError500() async throws {
        let recorder = StubProtocol.Recorder()
        let resp = try makeJSONResponse(status: 500, body: "{}")
        StubProtocol.install(recorder: recorder, steps: [.respond(resp)])
        defer { StubProtocol.reset() }

        let provider = AnthropicProvider(apiKey: "k", session: Self.stubSession())
        do {
            _ = try await provider.complete(LLMRequest(system: "s", user: "u"))
            Issue.record("Expected to throw")
        } catch let LLMError.transport(msg) {
            #expect(msg == "500")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private static func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }

    private func makeJSONResponse(
        status: Int,
        body: String,
        headers: [String: String] = [:]
    ) throws -> StubResponse {
        var allHeaders = headers
        allHeaders["Content-Type"] = allHeaders["Content-Type"] ?? "application/json"
        return StubResponse(status: status, headers: allHeaders, body: Data(body.utf8))
    }
}

// MARK: - URLProtocol stub

/// Payload describing how the stub should answer a request.
struct StubResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data
}

enum StubStep: Sendable {
    case respond(StubResponse)
}

/// A `URLProtocol` subclass that feeds scripted responses to tests.
///
/// Installation is process-global, so we serialize through an unfair lock and
/// expose ``install(recorder:steps:)`` / ``reset()`` helpers for the test case
/// to call in `defer` blocks.
final class StubProtocol: URLProtocol, @unchecked Sendable {

    // Globally installed state (one stub set per test at a time).
    private struct GlobalState {
        var recorder: Recorder?
        var steps: [StubStep] = []
    }
    private static let global = OSAllocatedUnfairLock(initialState: GlobalState())

    static func install(recorder: Recorder, steps: [StubStep]) {
        global.withLock { state in
            state.recorder = recorder
            state.steps = steps
        }
    }

    static func reset() {
        global.withLock { state in
            state.recorder = nil
            state.steps = []
        }
    }

    private static func popStep() -> StubStep? {
        global.withLock { state in
            guard !state.steps.isEmpty else { return nil }
            return state.steps.removeFirst()
        }
    }

    private static func record(_ request: URLRequest) {
        global.withLock { state in
            state.recorder?.record(request)
        }
    }

    // Recorder: captures every request seen by the protocol.
    final class Recorder: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: [CapturedRequest]())
        func record(_ req: URLRequest) {
            let captured = CapturedRequest(
                url: req.url,
                httpMethod: req.httpMethod,
                allHeaderFields: req.allHTTPHeaderFields ?? [:],
                bodyData: req.readBodyData()
            )
            lock.withLock { $0.append(captured) }
        }
        func allRequests() -> [CapturedRequest] {
            lock.withLock { $0 }
        }
    }

    // A `Sendable` snapshot of the interesting parts of a URLRequest.
    struct CapturedRequest: Sendable {
        let url: URL?
        let httpMethod: String?
        let allHeaderFields: [String: String]
        let bodyData: Data?
        func value(forHTTPHeaderField key: String) -> String? {
            // Case-insensitive lookup.
            if let v = allHeaderFields[key] { return v }
            for (k, v) in allHeaderFields where k.caseInsensitiveCompare(key) == .orderedSame {
                return v
            }
            return nil
        }
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.record(request)
        guard let step = Self.popStep() else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "StubProtocol",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No stub response queued"]
                )
            )
            return
        }
        switch step {
        case .respond(let r):
            guard let url = request.url,
                  let httpResponse = HTTPURLResponse(
                    url: url,
                    statusCode: r.status,
                    httpVersion: "HTTP/1.1",
                    headerFields: r.headers
                  )
            else {
                client?.urlProtocol(
                    self,
                    didFailWithError: NSError(domain: "StubProtocol", code: -2)
                )
                return
            }
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: r.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

// MARK: - URLRequest body extraction

private extension URLRequest {
    /// Returns the request body, preferring `httpBody` and falling back to
    /// draining `httpBodyStream` (which is what `URLProtocol` sees).
    func readBodyData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
