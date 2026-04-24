import Foundation
import Testing
@testable import ActivityMCP

@Suite("RateLimiter")
struct RateLimiterTests {
    @Test("allows calls within the limit")
    func allowsWithinLimit() async throws {
        let limiter = RateLimiter(limit: 3, window: 60)
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(limiter.allow(clientID: "c1", now: now))
        #expect(limiter.allow(clientID: "c1", now: now))
        #expect(limiter.allow(clientID: "c1", now: now))
    }

    @Test("denies once limit exceeded")
    func deniesOverLimit() async throws {
        let limiter = RateLimiter(limit: 2, window: 60)
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(limiter.allow(clientID: "c1", now: now))
        #expect(limiter.allow(clientID: "c1", now: now))
        #expect(limiter.allow(clientID: "c1", now: now) == false)
    }

    @Test("window expiry re-allows")
    func windowExpiryReallows() async throws {
        let limiter = RateLimiter(limit: 1, window: 10)
        let t0 = Date(timeIntervalSince1970: 1_000)
        #expect(limiter.allow(clientID: "c1", now: t0))
        #expect(limiter.allow(clientID: "c1", now: t0.addingTimeInterval(1)) == false)
        let t1 = t0.addingTimeInterval(11)
        #expect(limiter.allow(clientID: "c1", now: t1))
    }

    @Test("different client IDs isolated")
    func isolatedClients() async throws {
        let limiter = RateLimiter(limit: 1, window: 60)
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(limiter.allow(clientID: "a", now: now))
        #expect(limiter.allow(clientID: "b", now: now))
        #expect(limiter.allow(clientID: "a", now: now) == false)
    }
}
