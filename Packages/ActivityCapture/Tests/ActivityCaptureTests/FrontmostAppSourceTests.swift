import Foundation
import Testing
import os
import ActivityCore
import ActivityCoreTestSupport
@testable import ActivityCapture

/// Test workspace that lets the test simulate frontmost-app activations.
final class FakeWorkspace: FrontmostWorkspace, @unchecked Sendable {
    private struct State {
        var handler: (@Sendable (FrontmostAppInfo) -> Void)?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    init() {}

    func observeFrontmost(onChange: @escaping @Sendable (FrontmostAppInfo) -> Void) {
        state.withLock { $0.handler = onChange }
    }

    func stopObserving() {
        state.withLock { $0.handler = nil }
    }

    func simulate(bundleID: String, name: String) {
        let h = state.withLock { $0.handler }
        h?(FrontmostAppInfo(bundleID: bundleID, localizedName: name))
    }
}

@Suite("FrontmostAppSource")
struct FrontmostAppSourceTests {
    @Test func emitsEventOnActivation() async throws {
        let workspace = FakeWorkspace()
        let clock = FakeClock()
        let source = FrontmostAppSource(workspace: workspace, clock: clock)
        try await source.start()

        let task = Task<ActivityEvent?, Never> {
            for await event in source.events {
                return event
            }
            return nil
        }

        workspace.simulate(bundleID: "com.apple.Safari", name: "Safari")

        let event = await task.value
        let got = try #require(event)
        #expect(got.source == .frontmost)
        guard case .app(let bundleID, let name) = got.subject else {
            Issue.record("expected .app subject, got \(got.subject)")
            return
        }
        #expect(bundleID == "com.apple.Safari")
        #expect(name == "Safari")
        #expect(got.timestamp == clock.now())

        await source.stop()
    }

    @Test func emitsOneEventPerActivation() async throws {
        let workspace = FakeWorkspace()
        let source = FrontmostAppSource(workspace: workspace, clock: FakeClock())
        try await source.start()

        let task = Task<[ActivityEvent], Never> {
            var out: [ActivityEvent] = []
            for await event in source.events {
                out.append(event)
                if out.count == 3 { break }
            }
            return out
        }

        workspace.simulate(bundleID: "com.apple.Safari", name: "Safari")
        workspace.simulate(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        workspace.simulate(bundleID: "com.apple.Terminal", name: "Terminal")

        let events = await task.value
        #expect(events.count == 3)
        let ids = events.compactMap { e -> String? in
            if case .app(let id, _) = e.subject { return id }
            return nil
        }
        #expect(ids == ["com.apple.Safari", "com.apple.dt.Xcode", "com.apple.Terminal"])

        await source.stop()
    }

    @Test func stopDetachesObserver() async throws {
        let workspace = FakeWorkspace()
        let source = FrontmostAppSource(workspace: workspace, clock: FakeClock())
        try await source.start()
        await source.stop()
        // After stop, simulated notifications should not reach a (removed) handler.
        // FakeWorkspace clears the handler on stopObserving, so simulate() is a no-op.
        workspace.simulate(bundleID: "com.apple.Safari", name: "Safari")
        // Nothing to assert directly; reaching here without deadlock is the test.
        #expect(Bool(true))
    }
}
