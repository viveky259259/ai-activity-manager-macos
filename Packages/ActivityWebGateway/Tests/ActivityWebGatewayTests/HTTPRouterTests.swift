import Foundation
import Testing
import ActivityCore
import ActivityIPC
@testable import ActivityWebGateway

@Suite("HTTPRouter")
struct HTTPRouterTests {

    private func makeRouter() -> (HTTPRouter, FakeIPCHandler) {
        let fake = FakeIPCHandler()
        return (HTTPRouter(handler: fake), fake)
    }

    @Test("GET /api/status returns the StatusResponse JSON")
    func statusEndpoint() async throws {
        let (router, fake) = makeRouter()
        fake.setStatusResponse(.init(
            sources: ["frontmost"],
            capturedEventCount: 17,
            actionsEnabled: true,
            permissions: ["accessibility": "granted"]
        ))

        let resp = await router.dispatch(method: "GET", path: "/api/status", query: [:])

        #expect(resp.status == 200)
        let decoded = try JSONDecoder().decode(StatusResponse.self, from: resp.body)
        #expect(decoded.capturedEventCount == 17)
        #expect(decoded.actionsEnabled == true)
        #expect(fake.calls.status == 1)
    }

    @Test("GET /api/processes maps query params to ProcessesQuery")
    func processesEndpointMapsQuery() async throws {
        let (router, fake) = makeRouter()
        let resp = await router.dispatch(
            method: "GET",
            path: "/api/processes",
            query: ["sort": "name", "order": "asc", "limit": "5"]
        )

        #expect(resp.status == 200)
        let captured = try #require(fake.calls.listProcesses.first)
        #expect(captured.sortBy == .name)
        #expect(captured.order == .asc)
        #expect(captured.limit == 5)
    }

    @Test("unknown path returns 404 with JSON error body")
    func unknownPath() async throws {
        let (router, _) = makeRouter()
        let resp = await router.dispatch(method: "GET", path: "/api/nope", query: [:])
        #expect(resp.status == 404)
        let payload = try JSONDecoder().decode([String: String].self, from: resp.body)
        #expect(payload["error"]?.contains("/api/nope") == true)
    }

    @Test("non-GET methods return 405")
    func nonGetRejected() async throws {
        let (router, _) = makeRouter()
        let resp = await router.dispatch(method: "POST", path: "/api/status", query: [:])
        #expect(resp.status == 405)
    }
}
