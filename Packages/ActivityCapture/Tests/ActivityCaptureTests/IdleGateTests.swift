import Foundation
import Testing
import ActivityCore
@testable import ActivityCapture

@Suite("IdleGate collapses raw idle samples")
struct IdleGateTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(_ offset: TimeInterval, _ seconds: TimeInterval) -> IdleSample {
        IdleSample(timestamp: base.addingTimeInterval(offset), secondsSinceLastEvent: seconds)
    }

    @Test func noIdle_emitsNothing() {
        let gate = IdleGate(threshold: 120)
        var all: [ActivityEvent] = []
        all.append(contentsOf: gate.ingest(sample: sample(0, 0)))
        all.append(contentsOf: gate.ingest(sample: sample(10, 5)))
        all.append(contentsOf: gate.ingest(sample: sample(20, 30)))
        all.append(contentsOf: gate.ingest(sample: sample(30, 119)))
        #expect(all.isEmpty)
    }

    @Test func idleCrossingThreshold_emitsStartOnce() {
        let gate = IdleGate(threshold: 120)
        var events: [ActivityEvent] = []
        events.append(contentsOf: gate.ingest(sample: sample(0, 30)))
        events.append(contentsOf: gate.ingest(sample: sample(30, 125))) // crosses threshold
        events.append(contentsOf: gate.ingest(sample: sample(40, 135))) // still idle, no new event
        events.append(contentsOf: gate.ingest(sample: sample(50, 160))) // still idle, no new event

        #expect(events.count == 1)
        let event = try! #require(events.first)
        #expect(event.source == .idle)
        guard case .idleSpan(let startedAt, let endedAt) = event.subject else {
            Issue.record("expected idleSpan subject, got \(event.subject)")
            return
        }
        // idle began ~125s before timestamp of the crossing sample (at offset 30)
        let expectedStart = base.addingTimeInterval(30 - 125)
        #expect(abs(startedAt.timeIntervalSince(expectedStart)) < 0.001)
        #expect(endedAt == base.addingTimeInterval(30))
        #expect(event.attributes["idleTransition"] == "begin")
    }

    @Test func idleEnds_emitsEndEvent() {
        let gate = IdleGate(threshold: 120)
        _ = gate.ingest(sample: sample(0, 130)) // begin
        let endEvents = gate.ingest(sample: sample(60, 2)) // seconds dropped — end
        #expect(endEvents.count == 1)
        let event = try! #require(endEvents.first)
        #expect(event.source == .idle)
        #expect(event.attributes["idleTransition"] == "end")
        guard case .idleSpan(_, let endedAt) = event.subject else {
            Issue.record("expected idleSpan subject, got \(event.subject)")
            return
        }
        // Idle ended at the timestamp of the sample where seconds reset
        #expect(endedAt == base.addingTimeInterval(60))
    }

    @Test func rapidFlapping_pairsBeginsAndEnds() {
        let gate = IdleGate(threshold: 120)
        var events: [ActivityEvent] = []
        events.append(contentsOf: gate.ingest(sample: sample(0, 5)))
        events.append(contentsOf: gate.ingest(sample: sample(10, 125))) // begin #1
        events.append(contentsOf: gate.ingest(sample: sample(20, 3)))   // end #1
        events.append(contentsOf: gate.ingest(sample: sample(30, 5)))   // normal
        events.append(contentsOf: gate.ingest(sample: sample(40, 130))) // begin #2
        events.append(contentsOf: gate.ingest(sample: sample(50, 1)))   // end #2

        #expect(events.count == 4)
        #expect(events.map { $0.attributes["idleTransition"] } == ["begin", "end", "begin", "end"])
    }

    @Test func multipleThresholdCrossings_emitCorrectly() {
        let gate = IdleGate(threshold: 60)
        var events: [ActivityEvent] = []
        events.append(contentsOf: gate.ingest(sample: sample(0, 30)))
        events.append(contentsOf: gate.ingest(sample: sample(10, 65)))   // begin
        events.append(contentsOf: gate.ingest(sample: sample(20, 120)))  // still idle
        events.append(contentsOf: gate.ingest(sample: sample(30, 2)))    // end
        events.append(contentsOf: gate.ingest(sample: sample(40, 35)))   // below threshold
        events.append(contentsOf: gate.ingest(sample: sample(50, 80)))   // begin again

        let transitions = events.compactMap { $0.attributes["idleTransition"] }
        #expect(transitions == ["begin", "end", "begin"])
    }

    @Test func sustainedIdle_emitsSingleBegin() {
        let gate = IdleGate(threshold: 120)
        var events: [ActivityEvent] = []
        for step in stride(from: 0.0, through: 600.0, by: 10.0) {
            let seconds = step == 0 ? 5 : (step + 200) // first sample not idle, then very idle
            events.append(contentsOf: gate.ingest(sample: sample(step, seconds)))
        }
        let begins = events.filter { $0.attributes["idleTransition"] == "begin" }
        let ends = events.filter { $0.attributes["idleTransition"] == "end" }
        #expect(begins.count == 1)
        #expect(ends.isEmpty)
    }

    @Test func exactlyAtThreshold_isIdle() {
        let gate = IdleGate(threshold: 120)
        let events = gate.ingest(sample: sample(0, 120))
        #expect(events.count == 1)
        #expect(events.first?.attributes["idleTransition"] == "begin")
    }
}
