import Foundation
import Darwin
#if canImport(AppKit)
import AppKit
#endif

/// Live sampler backed by `libproc`. Enumerates every PID the caller can see,
/// pulls task info (memory / threads / cpu time) and BSD info (uid / comm),
/// resolves the full path via `proc_pidpath`, and cross-references
/// `NSWorkspace.runningApplications` so GUI apps display their localized names
/// and bundle IDs.
public struct LiveSystemProcessSampler: SystemProcessSampler {
    private let timebase: mach_timebase_info_data_t

    public init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        // Guard against the undocumented-but-possible zero denominator.
        if tb.denom == 0 { tb = mach_timebase_info_data_t(numer: 1, denom: 1) }
        self.timebase = tb
    }

    public func capture() -> [ProcessRawSample] {
        let pids = listAllPIDs()
        guard !pids.isEmpty else { return [] }

        let appLookup = buildAppLookup()
        var rows: [ProcessRawSample] = []
        rows.reserveCapacity(pids.count)

        var topMem: [Int32: UInt64]?

        for pid in pids where pid > 0 {
            if let row = sample(pid: pid, apps: appLookup) {
                rows.append(row)
            } else if let stub = restrictedStub(pid: pid, apps: appLookup) {
                // `top` is setuid root and can read phys_footprint for any
                // process, so we use it as a side-channel memory source for
                // PIDs where `proc_pid_rusage` returned EPERM.
                if topMem == nil { topMem = TopMemorySource.snapshot() }
                if let mem = topMem?[pid], mem > 0 {
                    rows.append(ProcessRawSample(
                        pid: stub.pid,
                        name: stub.name,
                        executablePath: stub.executablePath,
                        bundleID: stub.bundleID,
                        user: stub.user,
                        cpuNanos: 0,
                        memoryBytes: mem,
                        threads: 0,
                        isRestricted: true
                    ))
                } else {
                    rows.append(stub)
                }
            }
        }
        return rows
    }

    /// Built from `sysctl KERN_PROC_PID` which works without permissions —
    /// gives us the `comm` name and uid even when `proc_pidinfo` returns EACCES.
    private func restrictedStub(pid: pid_t, apps: [pid_t: AppInfo]) -> ProcessRawSample? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var kp = kinfo_proc()
        var kpSize = MemoryLayout<kinfo_proc>.size
        let ok = mib.withUnsafeMutableBufferPointer { buf in
            sysctl(buf.baseAddress, u_int(buf.count), &kp, &kpSize, nil, 0)
        }
        guard ok == 0, kpSize > 0 else { return nil }
        let commName = withUnsafePointer(to: &kp.kp_proc.p_comm) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let app = apps[pid]
        let name: String = {
            if let localized = app?.localizedName, !localized.isEmpty { return localized }
            if !commName.isEmpty { return commName }
            return "pid \(pid)"
        }()
        let uid = kp.kp_eproc.e_pcred.p_ruid
        return ProcessRawSample(
            pid: pid,
            name: name,
            executablePath: "",
            bundleID: app?.bundleID,
            user: username(for: uid),
            cpuNanos: 0,
            memoryBytes: 0,
            threads: 0,
            isRestricted: true
        )
    }

    // MARK: - PID enumeration

    private func listAllPIDs() -> [pid_t] {
        // `proc_listallpids` returns the PID count (not bytes), both for the
        // sizing call with (NULL, 0) and the filling call. Its buffer size
        // parameter, however, is in bytes — that asymmetry is the footgun.
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return [] }
        // Overallocate — the set can grow between the two calls.
        let capacity = Int(pidCount) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let byteSize = Int32(capacity * MemoryLayout<pid_t>.size)
        let used = pids.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_listallpids(buf.baseAddress, byteSize)
        }
        guard used > 0 else { return [] }
        return Array(pids.prefix(Int(used)))
    }

    // MARK: - Per-PID sampling

    private func sample(pid: pid_t, apps: [pid_t: AppInfo]) -> ProcessRawSample? {
        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let tiRead = withUnsafeMutablePointer(to: &taskInfo) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ptr, taskInfoSize)
        }
        guard tiRead == taskInfoSize else { return nil }

        let cpuAbs = taskInfo.pti_total_user &+ taskInfo.pti_total_system
        let cpuNanos = cpuAbs &* UInt64(timebase.numer) / UInt64(timebase.denom)

        var bsdInfo = proc_bsdinfo()
        let bsdInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let biRead = withUnsafeMutablePointer(to: &bsdInfo) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, bsdInfoSize)
        }
        let uid = biRead == bsdInfoSize ? bsdInfo.pbi_uid : 0
        let user = username(for: uid)
        let commName: String = biRead == bsdInfoSize
            ? withUnsafePointer(to: &bsdInfo.pbi_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
              }
            : ""

        let path = readPath(pid: pid)

        // `pti_resident_size` is RSS, which overcounts shared memory and
        // misses compressed pages — Activity Monitor's "Memory" column uses
        // `phys_footprint` from `proc_pid_rusage`, which is what users expect.
        let memoryBytes = physFootprint(pid: pid) ?? UInt64(taskInfo.pti_resident_size)

        let app = apps[pid]
        let name: String = {
            if let localized = app?.localizedName, !localized.isEmpty { return localized }
            if !commName.isEmpty { return commName }
            if !path.isEmpty { return (path as NSString).lastPathComponent }
            return "pid \(pid)"
        }()

        return ProcessRawSample(
            pid: pid,
            name: name,
            executablePath: path,
            bundleID: app?.bundleID,
            user: user,
            cpuNanos: cpuNanos,
            memoryBytes: memoryBytes,
            threads: Int(taskInfo.pti_threadnum)
        )
    }

    // MARK: - Helpers

    /// Returns the process's physical footprint — what Activity Monitor labels
    /// "Memory". Falls back to `nil` when `proc_pid_rusage` denies the read
    /// (kernel tasks, sandboxed peers without entitlements), so the caller can
    /// drop back to RSS.
    private func physFootprint(pid: pid_t) -> UInt64? {
        var rusage = rusage_info_current()
        let ok = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard ok == 0 else { return nil }
        return rusage.ri_phys_footprint
    }

    private func readPath(pid: pid_t) -> String {
        let cap = Int(kPidPathInfoMaxSize)
        var buf = [CChar](repeating: 0, count: cap)
        let n = buf.withUnsafeMutableBufferPointer { bp -> Int32 in
            proc_pidpath(pid, bp.baseAddress, UInt32(cap))
        }
        guard n > 0 else { return "" }
        let bytes = buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func username(for uid: UInt32) -> String {
        if let pw = getpwuid(uid), let nameC = pw.pointee.pw_name {
            return String(cString: nameC)
        }
        return "\(uid)"
    }

    private struct AppInfo {
        let bundleID: String?
        let localizedName: String?
    }

    private func buildAppLookup() -> [pid_t: AppInfo] {
        #if canImport(AppKit)
        var map: [pid_t: AppInfo] = [:]
        for app in NSWorkspace.shared.runningApplications {
            map[app.processIdentifier] = AppInfo(
                bundleID: app.bundleIdentifier,
                localizedName: app.localizedName
            )
        }
        return map
        #else
        return [:]
        #endif
    }
}

// `PROC_PIDPATHINFO_MAXSIZE` is declared as a bare macro in `<sys/proc_info.h>`
// and doesn't import into Swift on current SDKs. It's `4 * MAXPATHLEN`.
private let kPidPathInfoMaxSize: Int32 = 4 * 1024
