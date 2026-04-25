import Foundation
import ActivityMCP

/// One audit record published to every subscriber. Mirrors the
/// `AuditLogger.record(tool:params:outcome:)` arguments and adds a timestamp
/// so the UI can render the live feed without re-deriving it.
public struct AuditRecord: Sendable, Codable {
    public let tool: String
    public let params: JSONValue
    public let outcome: String
    public let timestamp: Date

    public init(tool: String, params: JSONValue, outcome: String, timestamp: Date) {
        self.tool = tool
        self.params = params
        self.outcome = outcome
        self.timestamp = timestamp
    }
}

/// Subscription handle returned by `BroadcastingAuditLogger.subscribe()`.
/// The caller iterates `events` to receive new records and uses `id` to
/// unsubscribe when the WebSocket closes.
public struct AuditSubscription: Sendable {
    public let id: UUID
    public let events: AsyncStream<AuditRecord>
}

/// Fan-out `AuditLogger`. Every recorded call is delivered to every active
/// subscriber. Late subscribers do not see records emitted before they
/// subscribed — this is a live feed, not a replay.
///
/// Used by `ActivityWebGateway` to push the live MCP audit trail to the
/// Flutter UI over `/ws/events` without coupling MCP to networking.
public actor BroadcastingAuditLogger: AuditLogger {
    private struct Subscriber {
        let continuation: AsyncStream<AuditRecord>.Continuation
    }

    private var subscribers: [UUID: Subscriber] = [:]
    private let clock: @Sendable () -> Date

    public init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    public func subscribe() -> AuditSubscription {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AuditRecord>.makeStream()
        subscribers[id] = Subscriber(continuation: continuation)
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.unsubscribe(id: id) }
        }
        return AuditSubscription(id: id, events: stream)
    }

    public func unsubscribe(id: UUID) {
        guard let sub = subscribers.removeValue(forKey: id) else { return }
        sub.continuation.finish()
    }

    public func record(tool: String, params: JSONValue, outcome: String) async {
        let entry = AuditRecord(
            tool: tool, params: params, outcome: outcome, timestamp: clock()
        )
        for sub in subscribers.values {
            sub.continuation.yield(entry)
        }
    }
}
