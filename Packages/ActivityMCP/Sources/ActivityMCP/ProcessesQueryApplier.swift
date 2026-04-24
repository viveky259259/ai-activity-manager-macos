import Foundation
import ActivityCore
import ActivityIPC

/// Pure transformation: given a raw `[ProcessSnapshot]` (already tagged with
/// categories by the caller) and a `ProcessesQuery`, produce the filtered,
/// sorted, and bounded list the MCP tool / IPC handler returns.
///
/// Extracting this out of the IPC layer lets us unit-test the query shape
/// without needing an XPC loop.
public enum ProcessesQueryApplier {
    /// Hard cap on page size regardless of what the client asks for — an
    /// unbounded request would happily pull 700+ processes across every
    /// invocation and dwarf the client's context window.
    public static let maxLimit = 500

    public static func apply(
        _ query: ProcessesQuery,
        to processes: [ProcessSnapshot]
    ) -> [ProcessSnapshot] {
        let filtered = processes.lazy.filter { proc in
            if !query.includeRestricted && proc.isRestricted { return false }
            if let min = query.minMemoryBytes, proc.memoryBytes < min { return false }
            if let cat = query.category, proc.category != cat { return false }
            return true
        }

        let sorted = filtered.sorted { lhs, rhs in
            let ascending: Bool
            switch query.sortBy {
            case .memory:
                ascending = lhs.memoryBytes < rhs.memoryBytes
            case .cpu:
                ascending = lhs.cpuPercent < rhs.cpuPercent
            case .name:
                ascending = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return query.order == .asc ? ascending : !ascending
        }

        let effectiveLimit = max(0, min(query.limit, maxLimit))
        return Array(sorted.prefix(effectiveLimit))
    }
}
