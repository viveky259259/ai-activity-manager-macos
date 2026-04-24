import Foundation
import Testing
import ActivityCore
@testable import ActivityIPC

/// End-to-end tests using an anonymous `NSXPCListener`. This exercises the real
/// NSXPC machinery (proxies, reply blocks, interface setup) without requiring a
/// Mach service registration, so it runs cleanly in CI or a sandboxed swift test
/// environment.
@Suite("IPC integration (anonymous XPC)")
struct IPCIntegrationTests {
    // MARK: helpers

    private func makePair(handler: any IPCHandler) -> (server: IPCServer, listener: NSXPCListener, client: IPCClient) {
        let server = IPCServer(handler: handler)
        let listener = server.makeListener()
        listener.resume()
        let client = IPCClient(endpoint: listener.endpoint)
        return (server, listener, client)
    }

    // MARK: tests

    @Test("status() round-trips through anonymous XPC")
    func statusRoundTrip() async throws {
        let fake = FakeIPCHandler()
        fake.setStatusResponse(StatusResponse(
            sources: ["frontmost", "idle"],
            capturedEventCount: 7,
            actionsEnabled: true,
            permissions: ["accessibility": "granted"]
        ))
        let (server, listener, client) = makePair(handler: fake)
        _ = server // retain
        defer {
            client.invalidate()
            listener.invalidate()
        }

        let response = try await client.status()

        #expect(response.sources == ["frontmost", "idle"])
        #expect(response.capturedEventCount == 7)
        #expect(response.actionsEnabled == true)
        #expect(response.permissions["accessibility"] == "granted")
        #expect(fake.calls.status == 1)
    }

    @Test("rules() round-trips through anonymous XPC")
    func rulesRoundTrip() async throws {
        let fake = FakeIPCHandler()
        let rule = Rule(
            name: "no slack at night",
            nlSource: "kill Slack after 9pm",
            trigger: .appFocused(bundleID: "com.tinyspeck.slackmacgap", durationAtLeast: nil),
            actions: [.killApp(bundleID: "com.tinyspeck.slackmacgap", strategy: .politeQuit, force: false)],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        fake.setRulesResponse(RulesResponse(rules: [rule]))
        let (server, listener, client) = makePair(handler: fake)
        _ = server
        defer { client.invalidate(); listener.invalidate() }

        let response = try await client.rules()

        #expect(response.rules.count == 1)
        #expect(response.rules.first?.id == rule.id)
        #expect(fake.calls.rules == 1)
    }

    @Test("addRule(_:) delivers the DTO to the handler and propagates the response")
    func addRuleRoundTrip() async throws {
        let fake = FakeIPCHandler()
        let createdAt = Date(timeIntervalSince1970: 42)
        let expectedRule = Rule(
            name: "auto",
            nlSource: "compiled",
            trigger: .focusModeChanged(to: nil),
            actions: [.logMessage("hi")],
            createdAt: createdAt,
            updatedAt: createdAt
        )
        fake.setAddRuleResponse(AddRuleResponse(rule: expectedRule))

        let (server, listener, client) = makePair(handler: fake)
        _ = server
        defer { client.invalidate(); listener.invalidate() }

        let sentRequest = AddRuleRequest(nl: "when focus changes, log hi")
        let response = try await client.addRule(sentRequest)

        #expect(response.rule.id == expectedRule.id)
        #expect(response.rule.name == "auto")
        #expect(fake.calls.addRule == [sentRequest])
    }

    @Test("killApp(_:) round-trips and preserves strategy + flags")
    func killAppRoundTrip() async throws {
        let fake = FakeIPCHandler()
        fake.setKillAppResponse(KillAppResponse(outcome: "succeeded"))

        let (server, listener, client) = makePair(handler: fake)
        _ = server
        defer { client.invalidate(); listener.invalidate() }

        let req = KillAppRequest(
            bundleID: "com.apple.Safari",
            strategy: .forceQuit,
            force: true,
            confirmed: true
        )
        let response = try await client.killApp(req)

        #expect(response.outcome == "succeeded")
        #expect(fake.calls.killApp == [req])
    }

    @Test("handler errors surface as thrown IPCError on the client")
    func handlerErrorsSurface() async throws {
        let fake = FakeIPCHandler()
        fake.stubError(forQuery: IPCError(code: "no_data", message: "nothing indexed yet"))

        let (server, listener, client) = makePair(handler: fake)
        _ = server
        defer { client.invalidate(); listener.invalidate() }

        let req = QueryRequest(
            question: "?",
            range: DateInterval(start: Date(timeIntervalSince1970: 0), duration: 1)
        )

        await #expect(throws: IPCError.self) {
            _ = try await client.query(req)
        }
    }

    @Test("Version mismatch: server rejects envelopes with the wrong protocol version")
    func versionMismatch() async throws {
        let fake = FakeIPCHandler()
        let (server, listener, _) = makePair(handler: fake)
        _ = server
        defer { listener.invalidate() }

        // Build a raw connection so we can send a hand-crafted envelope with a bad
        // version field. The typed IPCClient always stamps the current version, so
        // we bypass it here.
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = ActivityIPCInterface.make()
        connection.resume()
        defer { connection.invalidate() }

        let badEnvelope = IPCRequest(
            payload: AddRuleRequest(nl: "something"),
            requestID: UUID(),
            version: IPCProtocol.version + 99
        )
        let data = try IPCCoder.encoder().encode(badEnvelope)

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let service = proxy as? any ActivityIPCServiceProtocol else {
                continuation.resume(throwing: IPCError.internalError)
                return
            }
            service.addRule(data) { (replyData: Data) in
                continuation.resume(returning: replyData)
            }
        }

        let decoded = try IPCCoder.decoder().decode(IPCResponse<AddRuleResponse>.self, from: responseData)
        switch decoded.result {
        case .success:
            Issue.record("expected version_mismatch error but got success")
        case .error(let err):
            #expect(err == IPCError.versionMismatch)
        }

        #expect(fake.calls.addRule.isEmpty, "handler must not be invoked on version mismatch")
    }

    @Test("Server returns decode_failure for unparseable requests")
    func malformedRequestIsRejected() async throws {
        let fake = FakeIPCHandler()
        let (server, listener, _) = makePair(handler: fake)
        _ = server
        defer { listener.invalidate() }

        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = ActivityIPCInterface.make()
        connection.resume()
        defer { connection.invalidate() }

        let garbage = Data("not json".utf8)
        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let service = proxy as? any ActivityIPCServiceProtocol else {
                continuation.resume(throwing: IPCError.internalError)
                return
            }
            service.query(garbage) { replyData in
                continuation.resume(returning: replyData)
            }
        }

        let decoded = try IPCCoder.decoder().decode(IPCResponse<QueryResponse>.self, from: responseData)
        switch decoded.result {
        case .success: Issue.record("expected decode_failure but got success")
        case .error(let err): #expect(err.code == IPCError.decodeFailure.code)
        }
    }
}
