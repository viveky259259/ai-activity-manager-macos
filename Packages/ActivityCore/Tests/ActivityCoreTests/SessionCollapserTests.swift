import Testing
import Foundation
@testable import ActivityCore
import ActivityCoreTestSupport

@Suite("SessionCollapser")
struct SessionCollapserTests {
    let collapser = SessionCollapser()

    @Test("Empty input yields empty output")
    func emptyInput() {
        #expect(collapser.collapse([], gapThreshold: 60).isEmpty)
    }

    @Test("Single event produces single session")
    func singleEvent() {
        let e = Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0)
        let sessions = collapser.collapse([e], gapThreshold: 60)
        #expect(sessions.count == 1)
        #expect(sessions[0].sampleCount == 1)
        #expect(sessions[0].startedAt == e.timestamp)
        #expect(sessions[0].endedAt == e.timestamp)
    }

    @Test("Same subject within gap merges into one session")
    func sameSubjectWithinGap() {
        let events = [
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 10),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 25),
        ]
        let sessions = collapser.collapse(events, gapThreshold: 30)
        #expect(sessions.count == 1)
        #expect(sessions[0].sampleCount == 3)
        #expect(sessions[0].duration == 25)
    }

    @Test("Gap greater than threshold splits sessions")
    func gapExceedsThresholdSplits() {
        let events = [
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 100),
        ]
        let sessions = collapser.collapse(events, gapThreshold: 30)
        #expect(sessions.count == 2)
    }

    @Test("Different subjects never merge")
    func differentSubjectsSplit() {
        let events = [
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0),
            Fixtures.frontmost(bundleID: "com.b", name: "B", at: 5),
        ]
        let sessions = collapser.collapse(events, gapThreshold: 60)
        #expect(sessions.count == 2)
    }

    @Test("Out-of-order input is sorted before collapsing")
    func outOfOrderInput() {
        let events = [
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 30),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 15),
        ]
        let sessions = collapser.collapse(events, gapThreshold: 60)
        #expect(sessions.count == 1)
        #expect(sessions[0].startedAt == Fixtures.epoch)
        #expect(sessions[0].sampleCount == 3)
    }

    @Test("Gap exactly at threshold still merges")
    func gapExactlyAtThresholdMerges() {
        let events = [
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0),
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 60),
        ]
        let sessions = collapser.collapse(events, gapThreshold: 60)
        #expect(sessions.count == 1)
        #expect(sessions[0].duration == 60)
    }
}
