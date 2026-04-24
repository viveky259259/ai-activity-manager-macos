import Testing
import Foundation
import ActivityCore
import ActivityIPC
@testable import AMCTLCore

@Suite("OutputFormatter")
struct OutputFormatterTests {

    @Test("status human format lists sources and counts")
    func statusHuman() {
        let resp = StatusResponse(
            sources: ["frontmost", "idle"],
            capturedEventCount: 42,
            actionsEnabled: true,
            permissions: ["accessibility": "granted", "screen": "denied"]
        )
        let out = OutputFormatter.format(resp, as: .human)
        #expect(out.contains("Sources:"))
        #expect(out.contains("frontmost"))
        #expect(out.contains("42"))
        #expect(out.contains("Actions Enabled:  yes"))
        #expect(out.contains("accessibility"))
        #expect(out.contains("granted"))
    }

    @Test("status json output is parseable and carries schema_version")
    func statusJSON() throws {
        let resp = StatusResponse(
            sources: ["frontmost"],
            capturedEventCount: 1,
            actionsEnabled: false,
            permissions: ["accessibility": "granted"]
        )
        let out = OutputFormatter.format(resp, as: .json)
        let data = try #require(out.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dict = try #require(decoded)
        #expect(dict["schema_version"] as? Int == 1)
        #expect(dict["captured_event_count"] as? Int == 1)
        #expect(dict["actions_enabled"] as? Bool == false)
    }

    @Test("timeline ndjson emits one session per line")
    func timelineNdjson() {
        let s1 = ActivitySession(
            subject: .app(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_060),
            sampleCount: 5
        )
        let s2 = ActivitySession(
            subject: .app(bundleID: "com.apple.Safari", name: "Safari"),
            startedAt: Date(timeIntervalSince1970: 1_700_000_060),
            endedAt: Date(timeIntervalSince1970: 1_700_000_120),
            sampleCount: 2
        )
        let resp = TimelineResponse(sessions: [s1, s2])
        let out = OutputFormatter.format(resp, as: .ndjson)
        let lines = out.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        // Every line must be parseable JSON.
        for line in lines {
            let data = Data(line.utf8)
            #expect(throws: Never.self) {
                _ = try JSONSerialization.jsonObject(with: data)
            }
        }
    }

    @Test("empty timeline human output is stable")
    func emptyTimelineHuman() {
        let out = OutputFormatter.format(TimelineResponse(sessions: []), as: .human)
        #expect(out.contains("No sessions."))
    }
}
