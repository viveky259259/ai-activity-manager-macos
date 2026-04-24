import Foundation
import Testing
import ActivityIPC
@testable import ActivityMCP

@Suite("DefaultMCPHandler audit + rate limit")
struct DefaultMCPHandlerAuditRateLimitTests {

    final class RecordingAuditLogger: AuditLogger, @unchecked Sendable {
        struct Entry: Sendable {
            let tool: String
            let outcome: String
        }
        private let box = OSLock<[Entry]>(initial: [])
        func record(tool: String, params: JSONValue, outcome: String) async {
            box.with { $0.append(.init(tool: tool, outcome: outcome)) }
        }
        var entries: [Entry] { box.with { $0 } }
    }

    /// Thin wrapper around `os.OSAllocatedUnfairLock` for test helpers so
    /// Swift strict concurrency sees a clean Sendable box.
    final class OSLock<T>: @unchecked Sendable {
        private var value: T
        private let nsLock = NSLock()
        init(initial: T) { self.value = initial }
        func with<R>(_ body: (inout T) -> R) -> R {
            nsLock.lock(); defer { nsLock.unlock() }
            return body(&value)
        }
    }

    private func makeHandler(
        audit: (any AuditLogger)? = nil,
        readLimit: Int = 60,
        writeLimit: Int = 10
    ) -> (DefaultMCPHandler, FakeActivityClient) {
        let client = FakeActivityClient()
        client.setStatus(StatusResponse(
            sources: [], capturedEventCount: 0,
            actionsEnabled: true, permissions: [:]
        ))
        let registry = ToolRegistry()
        for t in ReadTools.make(client: client) { registry.register(t) }
        for t in WriteTools.make(client: client) { registry.register(t) }
        let handler = DefaultMCPHandler(
            registry: registry,
            auditLogger: audit ?? NullAuditLogger(),
            readLimiter: RateLimiter(limit: readLimit, window: 60),
            writeLimiter: RateLimiter(limit: writeLimit, window: 60)
        )
        return (handler, client)
    }

    private func callRequest(id: Int, name: String, args: JSONValue = .object([:])) -> JSONRPCRequest {
        JSONRPCRequest(
            id: .int(id),
            method: "tools/call",
            params: .object(["name": .string(name), "arguments": args])
        )
    }

    // MARK: - Audit

    @Test("successful tools/call emits one audit entry with the tool name")
    func auditOnSuccess() async throws {
        let audit = RecordingAuditLogger()
        let (handler, _) = makeHandler(audit: audit)

        _ = await handler.handle(request: callRequest(id: 1, name: "current_activity"))

        #expect(audit.entries.count == 1)
        #expect(audit.entries.first?.tool == "current_activity")
        #expect(audit.entries.first?.outcome == "succeeded")
    }

    @Test("failed tools/call emits audit entry with error outcome")
    func auditOnFailure() async throws {
        let audit = RecordingAuditLogger()
        let (handler, _) = makeHandler(audit: audit)

        // Unknown tool name → registry returns method-not-found.
        _ = await handler.handle(request: callRequest(id: 2, name: "no_such_tool"))

        #expect(audit.entries.count == 1)
        #expect(audit.entries.first?.tool == "no_such_tool")
        #expect(audit.entries.first?.outcome.hasPrefix("error") == true)
    }

    // MARK: - Rate limits

    @Test("read rate-limit rejects the call without dispatching")
    func readRateLimitRejects() async throws {
        let audit = RecordingAuditLogger()
        let (handler, client) = makeHandler(audit: audit, readLimit: 1)

        // First call consumes the single-slot quota.
        _ = await handler.handle(request: callRequest(id: 1, name: "current_activity"))
        let before = client.calls.status
        // Second call must be rejected without hitting the tool.
        let resp = await handler.handle(request: callRequest(id: 2, name: "current_activity"))
        let after = client.calls.status

        #expect(resp?.error != nil)
        #expect(before == after, "rate-limited call must not dispatch to client")
        // Both calls were audited — the second with a rate-limit outcome.
        #expect(audit.entries.count == 2)
        #expect(audit.entries.last?.outcome == "rate_limited")
    }

    @Test("write rate-limit rejects the call without dispatching")
    func writeRateLimitRejects() async throws {
        let (handler, client) = makeHandler(writeLimit: 1)
        // Enable kill_app for the duration of the test.
        handler.registry.setEnabled(name: "kill_app", enabled: true)

        let args: JSONValue = .object([
            "bundle_id": .string("com.example"),
            "confirmed": .bool(true),
        ])
        _ = await handler.handle(request: callRequest(id: 1, name: "kill_app", args: args))
        let before = client.calls.killApp.count
        let resp = await handler.handle(request: callRequest(id: 2, name: "kill_app", args: args))
        let after = client.calls.killApp.count

        #expect(resp?.error != nil)
        #expect(before == after, "rate-limited write must not dispatch")
    }
}
