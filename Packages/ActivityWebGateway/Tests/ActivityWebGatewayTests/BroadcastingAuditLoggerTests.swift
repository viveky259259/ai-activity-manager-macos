import Foundation
import Testing
import ActivityMCP
@testable import ActivityWebGateway

@Suite("BroadcastingAuditLogger")
struct BroadcastingAuditLoggerTests {

    @Test("fans out one record to every subscriber")
    func fanOutToAllSubscribers() async throws {
        let logger = BroadcastingAuditLogger()
        let a = await logger.subscribe()
        let b = await logger.subscribe()

        await logger.record(tool: "current_activity", params: .object([:]), outcome: "succeeded")

        var aIter = a.events.makeAsyncIterator()
        var bIter = b.events.makeAsyncIterator()
        let firstA = await aIter.next()
        let firstB = await bIter.next()

        #expect(firstA?.tool == "current_activity")
        #expect(firstA?.outcome == "succeeded")
        #expect(firstB?.tool == "current_activity")
    }

    @Test("late subscriber does not receive records emitted before subscribing")
    func lateSubscriberMissesPriorRecords() async throws {
        let logger = BroadcastingAuditLogger()
        await logger.record(tool: "current_activity", params: .object([:]), outcome: "succeeded")

        let late = await logger.subscribe()
        await logger.record(tool: "list_processes", params: .object([:]), outcome: "succeeded")

        var iter = late.events.makeAsyncIterator()
        let next = await iter.next()
        #expect(next?.tool == "list_processes")
    }

    @Test("unsubscribing stops further deliveries")
    func unsubscribeStopsDeliveries() async throws {
        let logger = BroadcastingAuditLogger()
        let stream = await logger.subscribe()
        let id = stream.id

        await logger.unsubscribe(id: id)
        await logger.record(tool: "current_activity", params: .object([:]), outcome: "succeeded")

        // After unsubscribe the stream completes; iteration returns nil promptly.
        var iter = stream.events.makeAsyncIterator()
        let next = await iter.next()
        #expect(next == nil)
    }
}
