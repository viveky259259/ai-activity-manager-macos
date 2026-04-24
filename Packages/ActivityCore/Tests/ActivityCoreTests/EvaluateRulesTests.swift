import Testing
import Foundation
@testable import ActivityCore
import ActivityCoreTestSupport

@Suite("EvaluateRules")
struct EvaluateRulesTests {

    @Test("Active rule dispatches action on trigger match")
    func activeRuleDispatch() async {
        let executor = FakeExecutor()
        let clock = FakeClock()
        let engine = EvaluateRules(executor: executor, clock: clock)
        let rule = Fixtures.rule(
            trigger: .appFocused(bundleID: "com.apple.Xcode", durationAtLeast: nil),
            actions: [.logMessage("hi")],
            mode: .active
        )
        await engine.load([rule])
        let dispatches = await engine.handle(
            Fixtures.frontmost(bundleID: "com.apple.Xcode", name: "Xcode", at: 0)
        )
        #expect(dispatches.count == 1)
        #expect(executor.executedActions.count == 1)
    }

    @Test("DryRun rule does not invoke executor")
    func dryRunSkipsExecutor() async {
        let executor = FakeExecutor()
        let engine = EvaluateRules(executor: executor, clock: FakeClock())
        let rule = Fixtures.rule(
            trigger: .appFocused(bundleID: "com.apple.Xcode", durationAtLeast: nil),
            actions: [.logMessage("hi")],
            mode: .dryRun
        )
        await engine.load([rule])
        let dispatches = await engine.handle(
            Fixtures.frontmost(bundleID: "com.apple.Xcode", name: "Xcode", at: 0)
        )
        #expect(dispatches.count == 1)
        if case .dryRun = dispatches[0].outcome {} else { Issue.record("expected dryRun outcome") }
        #expect(executor.executedActions.isEmpty)
    }

    @Test("Non-matching events produce no dispatches")
    func noMatch() async {
        let executor = FakeExecutor()
        let engine = EvaluateRules(executor: executor, clock: FakeClock())
        let rule = Fixtures.rule(
            trigger: .appFocused(bundleID: "com.a", durationAtLeast: nil),
            actions: [.logMessage("hi")],
            mode: .active
        )
        await engine.load([rule])
        let dispatches = await engine.handle(
            Fixtures.frontmost(bundleID: "com.b", name: "B", at: 0)
        )
        #expect(dispatches.isEmpty)
        #expect(executor.executedActions.isEmpty)
    }

    @Test("Disabled rules are ignored")
    func disabledRule() async {
        let executor = FakeExecutor()
        let engine = EvaluateRules(executor: executor, clock: FakeClock())
        let rule = Fixtures.rule(
            trigger: .appFocused(bundleID: "com.a", durationAtLeast: nil),
            actions: [.logMessage("hi")],
            mode: .disabled
        )
        await engine.load([rule])
        let dispatches = await engine.handle(
            Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0)
        )
        #expect(dispatches.isEmpty)
    }

    @Test("Cooldown prevents double-firing")
    func cooldownBlocks() async {
        let executor = FakeExecutor()
        let clock = FakeClock()
        let engine = EvaluateRules(executor: executor, clock: clock)
        let rule = Fixtures.rule(
            trigger: .appFocused(bundleID: "com.a", durationAtLeast: nil),
            actions: [.logMessage("hi")],
            mode: .active,
            cooldown: 60
        )
        await engine.load([rule])
        _ = await engine.handle(Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0))
        clock.advance(10)
        let second = await engine.handle(Fixtures.frontmost(bundleID: "com.a", name: "A", at: 10))
        #expect(second.isEmpty)
        clock.advance(61)
        let third = await engine.handle(Fixtures.frontmost(bundleID: "com.a", name: "A", at: 71))
        #expect(third.count == 1)
    }

    @Test("Condition tree gates dispatch (and)")
    func conditionAnd() async {
        let executor = FakeExecutor()
        let engine = EvaluateRules(executor: executor, clock: FakeClock())
        var rule = Fixtures.rule(
            trigger: .appFocused(bundleID: "com.a", durationAtLeast: nil),
            actions: [.logMessage("hi")],
            mode: .active
        )
        rule.condition = .and([
            .custom(key: "workspace", op: .eq, value: "prod"),
        ])
        await engine.load([rule])

        let miss = ActivityEvent(
            timestamp: Fixtures.epoch,
            source: .frontmost,
            subject: .app(bundleID: "com.a", name: "A"),
            attributes: ["workspace": "dev"]
        )
        #expect((await engine.handle(miss)).isEmpty)

        let hit = ActivityEvent(
            timestamp: Fixtures.epoch.addingTimeInterval(120),
            source: .frontmost,
            subject: .app(bundleID: "com.a", name: "A"),
            attributes: ["workspace": "prod"]
        )
        #expect(!(await engine.handle(hit)).isEmpty)
    }

    @Test("Idle transitions map to correct trigger kinds")
    func idleTriggers() async {
        let executor = FakeExecutor()
        let engine = EvaluateRules(executor: executor, clock: FakeClock())
        let rule = Fixtures.rule(
            trigger: .idleEntered(after: 60),
            actions: [.logMessage("slept")],
            mode: .active
        )
        await engine.load([rule])
        let d = await engine.handle(Fixtures.idle(transition: "entered", at: 0))
        #expect(d.count == 1)
        let none = await engine.handle(Fixtures.idle(transition: "ended", at: 100))
        #expect(none.isEmpty)
    }

    @Test("Multiple actions per rule dispatch in order")
    func multipleActions() async {
        let executor = FakeExecutor()
        let engine = EvaluateRules(executor: executor, clock: FakeClock())
        let rule = Fixtures.rule(
            trigger: .appFocused(bundleID: "com.a", durationAtLeast: nil),
            actions: [.logMessage("1"), .logMessage("2"), .logMessage("3")],
            mode: .active
        )
        await engine.load([rule])
        let d = await engine.handle(Fixtures.frontmost(bundleID: "com.a", name: "A", at: 0))
        #expect(d.count == 3)
        #expect(executor.executedActions.count == 3)
    }
}
