import Foundation
import ActivityIPC

/// Builds a default `IPCClient` connected to the registered Mach service. Kept
/// as a helper so commands can re-use one construction path.
public enum ClientFactory {
    public static func makeClient() -> IPCClient {
        IPCClient(machServiceName: IPCProtocol.machServiceName)
    }
}

/// Parse an ISO8601 timestamp (with or without fractional seconds).
public enum DateParsing {
    public static func iso8601(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f2.date(from: s)
    }

    /// Resolve a period shorthand like `today`, `7d`, `30d`, `24h` to a
    /// `DateInterval` ending at ``now``.
    public static func period(_ s: String, now: Date = Date()) -> DateInterval? {
        let trimmed = s.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == "today" {
            let start = Calendar.current.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        }
        guard let unit = trimmed.last else { return nil }
        let prefix = String(trimmed.dropLast())
        guard let n = Int(prefix), n > 0 else { return nil }
        let secondsPer: TimeInterval
        switch unit {
        case "h": secondsPer = 3600
        case "d": secondsPer = 86_400
        case "w": secondsPer = 7 * 86_400
        default: return nil
        }
        return DateInterval(start: now.addingTimeInterval(-Double(n) * secondsPer), end: now)
    }
}
