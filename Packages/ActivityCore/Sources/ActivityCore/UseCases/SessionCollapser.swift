import Foundation

public struct SessionCollapser: Sendable {
    public init() {}

    public func collapse(
        _ events: [ActivityEvent],
        gapThreshold: TimeInterval
    ) -> [ActivitySession] {
        guard !events.isEmpty else { return [] }
        let sorted = events.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.timestamp < rhs.timestamp
        }

        var sessions: [ActivitySession] = []
        var current: (subject: ActivityEvent.Subject, start: Date, end: Date, count: Int)?

        for event in sorted {
            if var c = current {
                if c.subject == event.subject && event.timestamp.timeIntervalSince(c.end) <= gapThreshold {
                    c.end = event.timestamp
                    c.count += 1
                    current = c
                } else {
                    sessions.append(ActivitySession(
                        subject: c.subject,
                        startedAt: c.start,
                        endedAt: c.end,
                        sampleCount: c.count
                    ))
                    current = (event.subject, event.timestamp, event.timestamp, 1)
                }
            } else {
                current = (event.subject, event.timestamp, event.timestamp, 1)
            }
        }

        if let c = current {
            sessions.append(ActivitySession(
                subject: c.subject,
                startedAt: c.start,
                endedAt: c.end,
                sampleCount: c.count
            ))
        }

        return sessions
    }
}
