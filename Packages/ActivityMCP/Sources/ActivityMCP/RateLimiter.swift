import Foundation
import os

/// Sliding-window rate limiter keyed by client ID. Per PRD §5: 60 read/min,
/// 10 write/min. The window slides on every call, so clients that pause will
/// recover their full quota as older hits fall out of the window.
public final class RateLimiter: @unchecked Sendable {
    public let limit: Int
    public let window: TimeInterval

    private struct Bucket {
        var hits: [Date] = []
    }

    private struct State {
        var buckets: [String: Bucket] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(limit: Int, window: TimeInterval) {
        self.limit = limit
        self.window = window
    }

    /// Returns true if the call is allowed; records the hit as a side-effect.
    public func allow(clientID: String, now: Date = Date()) -> Bool {
        state.withLock { s in
            var bucket = s.buckets[clientID, default: Bucket()]
            let cutoff = now.addingTimeInterval(-window)
            bucket.hits.removeAll { $0 < cutoff }
            guard bucket.hits.count < limit else {
                s.buckets[clientID] = bucket
                return false
            }
            bucket.hits.append(now)
            s.buckets[clientID] = bucket
            return true
        }
    }
}
