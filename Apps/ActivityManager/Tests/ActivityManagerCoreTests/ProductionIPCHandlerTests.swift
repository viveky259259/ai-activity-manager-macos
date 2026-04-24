import Foundation
import Testing
import ActivityCore
import ActivityStore
import ActivityIPC
import ActivityActions
import ActivityMCP
import ActivityCapture
@testable import ActivityManagerCore

@Suite("ProductionIPCHandler")
struct ProductionIPCHandlerTests {

    // MARK: - Fakes

    final class FakeSampler: SystemProcessSampler, @unchecked Sendable {
        let samples: [ProcessRawSample]
        init(_ samples: [ProcessRawSample]) { self.samples = samples }
        func capture() -> [ProcessRawSample] { samples }
    }

    private func makeHandler(
        store: SQLiteActivityStore? = nil,
        terminator: ProcessTerminator? = nil,
        sampler: SystemProcessSampler = FakeSampler([]),
        memory: SystemMemorySource.Snapshot? = nil
    ) throws -> (ProductionIPCHandler, SQLiteActivityStore, ScriptedProcessControl) {
        let realStore = try store ?? SQLiteActivityStore.temporary()
        let control = ScriptedProcessControl()
        let term = terminator ?? ProcessTerminator(control: control)
        let handler = ProductionIPCHandler(
            store: realStore,
            terminator: term,
            sampler: sampler,
            permissions: FakePermissionsChecker(),
            memorySource: { memory }
        )
        return (handler, realStore, control)
    }

    // MARK: - killApp: bundle vs pid

    @Test("killApp with bundle_id routes through ProcessTerminator.execute")
    func killAppByBundle() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 4242, bundleID: "com.example.toy")
        ])
        let term = ProcessTerminator(control: control)
        let (handler, _, _) = try makeHandler(terminator: term, sampler: FakeSampler([]))

        let resp = try await handler.killApp(
            KillAppRequest(bundleID: "com.example.toy", pid: nil,
                           strategy: .politeQuit, force: false, confirmed: true)
        )

        #expect(resp.outcome == "succeeded")
        #expect(control.terminateCalls.count == 1)
        #expect(control.terminateCalls.first?.pid == 4242)
    }

    @Test("killApp with pid routes through ProcessTerminator.killProcess")
    func killAppByPid() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 9001, bundleID: "com.example.pid")
        ])
        let term = ProcessTerminator(control: control)
        let (handler, _, _) = try makeHandler(terminator: term, sampler: FakeSampler([]))

        let resp = try await handler.killApp(
            KillAppRequest(bundleID: nil, pid: 9001,
                           strategy: .politeQuit, force: false, confirmed: true)
        )

        #expect(resp.outcome == "succeeded")
        #expect(control.terminateCalls.count == 1)
        #expect(control.terminateCalls.first?.pid == 9001)
    }

    @Test("killApp rejects when both bundle_id and pid are set")
    func killAppRejectsBothTargets() async throws {
        let (handler, _, _) = try makeHandler()
        do {
            _ = try await handler.killApp(
                KillAppRequest(bundleID: "com.example.toy", pid: 4242,
                               strategy: .politeQuit, force: false, confirmed: true)
            )
            Issue.record("expected error")
        } catch let ipc as IPCError {
            #expect(ipc.code == IPCError.invalidRequest.code)
        }
    }

    @Test("killApp rejects when neither bundle_id nor pid is set")
    func killAppRejectsMissingTarget() async throws {
        let (handler, _, _) = try makeHandler()
        do {
            _ = try await handler.killApp(
                KillAppRequest(bundleID: nil, pid: nil,
                               strategy: .politeQuit, force: false, confirmed: true)
            )
            Issue.record("expected error")
        } catch let ipc as IPCError {
            #expect(ipc.code == IPCError.invalidRequest.code)
        }
    }

    // MARK: - listProcesses

    @Test("listProcesses returns sampled processes with system memory snapshot")
    func listProcessesReturnsPage() async throws {
        let sampler = FakeSampler([
            ProcessRawSample(
                pid: 42, name: "Safari",
                executablePath: "/Applications/Safari.app/Contents/MacOS/Safari",
                bundleID: "com.apple.Safari", user: "vivek",
                cpuNanos: 0, memoryBytes: 1_024, threads: 8
            ),
        ])
        let mem = SystemMemorySource.Snapshot(usedBytes: 12_000_000_000, totalBytes: 16_000_000_000)
        let (handler, _, _) = try makeHandler(sampler: sampler, memory: mem)

        let page = try await handler.listProcesses(ProcessesQuery())

        #expect(page.processes.count == 1)
        #expect(page.processes.first?.pid == 42)
        #expect(page.processes.first?.bundleID == "com.apple.Safari")
        #expect(page.systemMemoryUsedBytes == 12_000_000_000)
        #expect(page.systemMemoryTotalBytes == 16_000_000_000)
    }

    @Test("listProcesses honours limit and sort order")
    func listProcessesSortAndLimit() async throws {
        let sampler = FakeSampler([
            ProcessRawSample(pid: 1, name: "a", executablePath: "",
                             bundleID: nil, user: "u",
                             cpuNanos: 0, memoryBytes: 100, threads: 1),
            ProcessRawSample(pid: 2, name: "b", executablePath: "",
                             bundleID: nil, user: "u",
                             cpuNanos: 0, memoryBytes: 500, threads: 1),
            ProcessRawSample(pid: 3, name: "c", executablePath: "",
                             bundleID: nil, user: "u",
                             cpuNanos: 0, memoryBytes: 300, threads: 1),
        ])
        let (handler, _, _) = try makeHandler(sampler: sampler)

        let page = try await handler.listProcesses(
            ProcessesQuery(sortBy: .memory, order: .desc, limit: 2)
        )

        #expect(page.processes.count == 2)
        #expect(page.processes.first?.pid == 2) // memoryBytes 500
        #expect(page.processes.last?.pid == 3)  // memoryBytes 300
    }

    // MARK: - Rules round-trip

    @Test("rules returns what the store has persisted")
    func rulesRoundTrip() async throws {
        let (handler, store, _) = try makeHandler()
        let rule = Rule(
            name: "seed", nlSource: "seed",
            trigger: .appFocused(bundleID: "com.example", durationAtLeast: nil),
            actions: [.logMessage("x")],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        try await store.upsertRule(rule)

        let got = try await handler.rules()
        #expect(got.rules.map { $0.id }.contains(rule.id))
    }

    @Test("deleteRule removes the rule from the store")
    func deleteRuleDelegates() async throws {
        let (handler, store, _) = try makeHandler()
        let rule = Rule(
            name: "doomed", nlSource: "",
            trigger: .idleEntered(after: 60),
            actions: [.logMessage("x")],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        try await store.upsertRule(rule)

        _ = try await handler.deleteRule(DeleteRuleRequest(id: rule.id))

        let remaining = try await store.rules()
        #expect(remaining.contains(where: { $0.id == rule.id }) == false)
    }
}
