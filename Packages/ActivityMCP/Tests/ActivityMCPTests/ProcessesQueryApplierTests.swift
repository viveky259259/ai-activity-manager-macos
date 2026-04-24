import Testing
import Foundation
import ActivityCore
import ActivityIPC
@testable import ActivityMCP

@Suite("ProcessesQueryApplier")
struct ProcessesQueryApplierTests {

    private func snap(
        pid: Int32,
        name: String,
        mem: UInt64 = 0,
        cpu: Double = 0,
        restricted: Bool = false,
        category: String? = nil
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid, bundleID: nil, name: name, user: "u",
            memoryBytes: mem, cpuPercent: cpu, threads: 1,
            isFrontmost: false, isRestricted: restricted, category: category
        )
    }

    @Test("sort by memory desc is the default")
    func sortMemoryDesc() {
        let input = [
            snap(pid: 1, name: "small", mem: 100),
            snap(pid: 2, name: "large", mem: 10_000),
            snap(pid: 3, name: "medium", mem: 1_000),
        ]
        let out = ProcessesQueryApplier.apply(ProcessesQuery(), to: input)
        #expect(out.map(\.pid) == [2, 3, 1])
    }

    @Test("sort by cpu asc")
    func sortCPUAsc() {
        let input = [
            snap(pid: 1, name: "a", cpu: 50),
            snap(pid: 2, name: "b", cpu: 2),
            snap(pid: 3, name: "c", cpu: 10),
        ]
        let q = ProcessesQuery(sortBy: .cpu, order: .asc)
        let out = ProcessesQueryApplier.apply(q, to: input)
        #expect(out.map(\.pid) == [2, 3, 1])
    }

    @Test("sort by name is case-insensitive")
    func sortName() {
        let input = [
            snap(pid: 1, name: "zeta"),
            snap(pid: 2, name: "Alpha"),
            snap(pid: 3, name: "beta"),
        ]
        let q = ProcessesQuery(sortBy: .name, order: .asc)
        let out = ProcessesQueryApplier.apply(q, to: input)
        #expect(out.map(\.pid) == [2, 3, 1])
    }

    @Test("limit caps the output")
    func limitCaps() {
        let input = (1...100).map { snap(pid: Int32($0), name: "p\($0)", mem: UInt64($0)) }
        let q = ProcessesQuery(limit: 5)
        let out = ProcessesQueryApplier.apply(q, to: input)
        #expect(out.count == 5)
    }

    @Test("limit coerced to max 500")
    func limitMax() {
        let input = (1...600).map { snap(pid: Int32($0), name: "p\($0)", mem: UInt64($0)) }
        let q = ProcessesQuery(limit: 10_000)
        let out = ProcessesQueryApplier.apply(q, to: input)
        #expect(out.count == 500)
    }

    @Test("category filter")
    func categoryFilter() {
        let input = [
            snap(pid: 1, name: "Safari", category: "browser"),
            snap(pid: 2, name: "Slack",  category: "communication"),
            snap(pid: 3, name: "Chrome", category: "browser"),
            snap(pid: 4, name: "Other",  category: nil),
        ]
        let q = ProcessesQuery(category: "browser")
        let out = ProcessesQueryApplier.apply(q, to: input)
        #expect(Set(out.map(\.pid)) == [1, 3])
    }

    @Test("include_restricted=false drops restricted rows")
    func excludeRestricted() {
        let input = [
            snap(pid: 1, name: "good"),
            snap(pid: 2, name: "locked", restricted: true),
        ]
        let q = ProcessesQuery(includeRestricted: false)
        let out = ProcessesQueryApplier.apply(q, to: input)
        #expect(out.map(\.pid) == [1])
    }

    @Test("min_memory_bytes filter")
    func minMemory() {
        let input = [
            snap(pid: 1, name: "tiny", mem: 100),
            snap(pid: 2, name: "big", mem: 1_000_000),
        ]
        let q = ProcessesQuery(minMemoryBytes: 500)
        let out = ProcessesQueryApplier.apply(q, to: input)
        #expect(out.map(\.pid) == [2])
    }
}
