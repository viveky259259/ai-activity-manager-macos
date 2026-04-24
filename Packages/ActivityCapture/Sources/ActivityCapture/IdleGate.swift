import Foundation
import os
import ActivityCore

/// Raw sample from an idle polling source: the wall-clock timestamp the sample
/// was taken plus the number of seconds the user has been idle at that moment.
public struct IdleSample: Hashable, Sendable {
    public let timestamp: Date
    public let secondsSinceLastEvent: TimeInterval

    public init(timestamp: Date, secondsSinceLastEvent: TimeInterval) {
        self.timestamp = timestamp
        self.secondsSinceLastEvent = secondsSinceLastEvent
    }
}

/// Pure-logic collapser that turns a stream of raw `(timestamp, seconds)`
/// samples into discrete "idle began" / "idle ended" `ActivityEvent`s.
///
/// - "begin" is emitted the first sample where `secondsSinceLastEvent >= threshold`.
/// - "end" is emitted on the first sample after a begin where seconds drop
///   below the threshold.
/// - Multiple consecutive samples above threshold collapse into a single begin.
public final class IdleGate: @unchecked Sendable {
    private struct State {
        var isIdle: Bool = false
        var currentIdleStartedAt: Date?
    }

    private let threshold: TimeInterval
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(threshold: TimeInterval = 120) {
        self.threshold = threshold
    }

    public func ingest(sample: IdleSample) -> [ActivityEvent] {
        state.withLock { s in
            let isNowIdle = sample.secondsSinceLastEvent >= threshold

            if isNowIdle && !s.isIdle {
                // Transition: active → idle. The idle period actually started
                // `secondsSinceLastEvent` ago.
                let startedAt = sample.timestamp.addingTimeInterval(-sample.secondsSinceLastEvent)
                s.isIdle = true
                s.currentIdleStartedAt = startedAt
                let event = ActivityEvent(
                    timestamp: sample.timestamp,
                    source: .idle,
                    subject: .idleSpan(startedAt: startedAt, endedAt: sample.timestamp),
                    attributes: ["idleTransition": "begin"]
                )
                return [event]
            }

            if !isNowIdle && s.isIdle {
                // Transition: idle → active.
                let startedAt = s.currentIdleStartedAt ?? sample.timestamp
                s.isIdle = false
                s.currentIdleStartedAt = nil
                let event = ActivityEvent(
                    timestamp: sample.timestamp,
                    source: .idle,
                    subject: .idleSpan(startedAt: startedAt, endedAt: sample.timestamp),
                    attributes: ["idleTransition": "end"]
                )
                return [event]
            }

            return []
        }
    }
}
