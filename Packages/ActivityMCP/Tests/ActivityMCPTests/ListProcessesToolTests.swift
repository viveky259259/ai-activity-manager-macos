import Foundation
import Testing
import ActivityCore
import ActivityIPC
@testable import ActivityMCP

@Suite("list_processes tool")
struct ListProcessesToolTests {

    private func tool(client: FakeActivityClient) throws -> ToolDefinition {
        let tools = ReadTools.make(client: client)
        return try #require(tools.first(where: { $0.name == "list_processes" }))
    }

    private func stubClient(with snapshots: [ProcessSnapshot] = []) -> FakeActivityClient {
        let client = FakeActivityClient()
        client.setListProcesses(
            ProcessesPage(
                processes: snapshots,
                systemMemoryUsedBytes: 12_000_000_000,
                systemMemoryTotalBytes: 16_000_000_000,
                sampledAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        return client
    }

    @Test("registered as a read-only tool")
    func registered() throws {
        let client = FakeActivityClient()
        let t = try tool(client: client)
        #expect(t.enabled)
        #expect(t.isWrite == false)
    }

    @Test("defaults map to ProcessesQuery with memory desc, limit 50")
    func defaultsMapToQuery() async throws {
        let client = stubClient()
        let t = try tool(client: client)

        _ = try await t.handler(.object([:]))

        let captured = try #require(client.capturedListProcessesRequest)
        #expect(captured.sortBy == .memory)
        #expect(captured.order == .desc)
        #expect(captured.limit == 50)
        #expect(captured.category == nil)
        #expect(captured.includeRestricted == true)
        #expect(captured.minMemoryBytes == nil)
    }

    @Test("explicit arguments forward through to ProcessesQuery")
    func explicitArgsForward() async throws {
        let client = stubClient()
        let t = try tool(client: client)

        let args: JSONValue = .object([
            "sort_by": .string("cpu"),
            "order": .string("asc"),
            "limit": .int(20),
            "category": .string("entertainment"),
            "include_restricted": .bool(false),
            "min_memory_bytes": .int(1_000_000),
        ])
        _ = try await t.handler(args)

        let captured = try #require(client.capturedListProcessesRequest)
        #expect(captured.sortBy == .cpu)
        #expect(captured.order == .asc)
        #expect(captured.limit == 20)
        #expect(captured.category == "entertainment")
        #expect(captured.includeRestricted == false)
        #expect(captured.minMemoryBytes == 1_000_000)
    }

    @Test("unknown sort_by falls back to memory desc")
    func unknownSortByFallsBack() async throws {
        let client = stubClient()
        let t = try tool(client: client)

        let args: JSONValue = .object([
            "sort_by": .string("nonsense"),
            "order": .string("weird"),
        ])
        _ = try await t.handler(args)

        let captured = try #require(client.capturedListProcessesRequest)
        #expect(captured.sortBy == .memory)
        #expect(captured.order == .desc)
    }

    @Test("limit above 500 is capped at the tool layer")
    func limitIsCapped() async throws {
        let client = stubClient()
        let t = try tool(client: client)

        _ = try await t.handler(.object(["limit": .int(10_000)]))

        let captured = try #require(client.capturedListProcessesRequest)
        #expect(captured.limit == 500)
    }

    @Test("response exposes processes and system memory")
    func responseShape() async throws {
        let snapshot = ProcessSnapshot(
            pid: 42,
            bundleID: "com.apple.Safari",
            name: "Safari",
            user: "vivek",
            memoryBytes: 1_024,
            cpuPercent: 3.5,
            threads: 12,
            isFrontmost: true,
            isRestricted: false,
            category: "browser"
        )
        let client = stubClient(with: [snapshot])
        let t = try tool(client: client)

        let result = try await t.handler(.object([:]))

        guard case .object(let obj) = result,
              case .array(let processes) = obj["processes"],
              case .object(let first) = processes.first else {
            Issue.record("expected processes array; got \(result)")
            return
        }

        #expect(processes.count == 1)
        #expect(first["pid"] == .int(42))
        #expect(first["bundle_id"] == .string("com.apple.Safari") || first["bundleID"] == .string("com.apple.Safari"))
        #expect(obj["system_memory_used_bytes"] != nil || obj["systemMemoryUsedBytes"] != nil)
        #expect(obj["system_memory_total_bytes"] != nil || obj["systemMemoryTotalBytes"] != nil)
    }
}
