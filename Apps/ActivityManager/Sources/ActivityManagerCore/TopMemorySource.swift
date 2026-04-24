import Foundation

/// Shells out to `/usr/bin/top` (setuid root) to recover memory values for
/// processes we can't read via `proc_pid_rusage` — i.e. those owned by other
/// users like `_windowserver`, `root`, or sandboxed system daemons. top's
/// `MEM` column mirrors Activity Monitor's "Memory" (phys_footprint).
///
/// One invocation per refresh cycle costs ~200ms of child-process time, which
/// is acceptable at a 2s refresh interval.
public struct TopMemorySource {
    /// Returns a snapshot mapping PID → memory bytes as reported by top.
    public static func snapshot() -> [Int32: UInt64] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        // -l 1     : single sample, exit immediately
        // -n 4000  : max rows to show. `-n 0` means "zero rows", not
        //            "unlimited" (costly footgun), so we pick a ceiling well
        //            above any real system's PID count.
        // -stats pid,mem : two whitespace-separated columns
        proc.arguments = ["-l", "1", "-n", "4000", "-stats", "pid,mem"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return [:]
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return [:] }

        var out: [Int32: UInt64] = [:]
        var sawHeader = false
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !sawHeader {
                // top prints a preamble block followed by a header row
                // starting with "PID". Skip everything up to and including it.
                if line.hasPrefix("PID") { sawHeader = true }
                continue
            }
            // Expected format: "<pid>  <mem>" with arbitrary whitespace.
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2,
                  let pid = Int32(parts[0]),
                  let bytes = parseMem(String(parts[1])) else { continue }
            out[pid] = bytes
        }
        return out
    }

    /// top's MEM column uses suffixes: "1065M", "12K", "23M", "2G", "3696K",
    /// or a bare integer (interpreted as bytes is wrong on macOS — top always
    /// includes a suffix on recent systems, but guard anyway).
    static func parseMem(_ s: String) -> UInt64? {
        guard let last = s.last else { return nil }
        let unit: UInt64
        let numberSubstr: Substring
        switch last {
        case "K", "k":
            unit = 1024
            numberSubstr = s.dropLast()
        case "M", "m":
            unit = 1024 * 1024
            numberSubstr = s.dropLast()
        case "G", "g":
            unit = 1024 * 1024 * 1024
            numberSubstr = s.dropLast()
        case "T", "t":
            unit = 1024 * 1024 * 1024 * 1024
            numberSubstr = s.dropLast()
        default:
            unit = 1  // bare digit — assume bytes, though top rarely emits this
            numberSubstr = Substring(s)
        }
        guard let value = Double(numberSubstr) else { return nil }
        return UInt64(value * Double(unit))
    }
}
