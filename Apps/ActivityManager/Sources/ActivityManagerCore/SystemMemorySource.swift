import Foundation
import Darwin.Mach

/// System-wide memory figure that mirrors Activity Monitor's "Memory Used".
/// Summing every process's `phys_footprint` overcounts: shared pages are
/// charged to multiple processes and compressed pages show up twice. The
/// kernel's own accounting (via `host_statistics64`) is what the OS actually
/// reports as pressure.
public enum SystemMemorySource {
    public struct Snapshot: Sendable {
        /// App + Wired + Compressed — matches Activity Monitor's "Memory Used".
        public let usedBytes: UInt64
        public let totalBytes: UInt64
    }

    public static func snapshot() -> Snapshot? {
        // Ask the host for its page size instead of reading the non-Sendable
        // `vm_kernel_page_size` global — same value, concurrency-safe.
        var hostPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &hostPageSize)
        let pageSize = UInt64(hostPageSize)
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        // Anonymous pages minus purgeable — Activity Monitor's "App Memory".
        let appPages = UInt64(stats.internal_page_count &- stats.purgeable_count)
        let appMemory = appPages * pageSize

        var totalBytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        var mib: [Int32] = [CTL_HW, HW_MEMSIZE]
        _ = mib.withUnsafeMutableBufferPointer { buf in
            sysctl(buf.baseAddress, u_int(buf.count), &totalBytes, &size, nil, 0)
        }

        return Snapshot(
            usedBytes: wired + compressed + appMemory,
            totalBytes: totalBytes
        )
    }
}
