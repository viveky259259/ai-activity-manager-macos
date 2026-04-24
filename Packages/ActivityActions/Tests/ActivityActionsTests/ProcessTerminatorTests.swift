import Testing
import Foundation
@testable import ActivityActions
import ActivityCore
import ActivityCoreTestSupport

@Suite("ProcessTerminator")
struct ProcessTerminatorTests {

    // MARK: - Happy path

    @Test("polite quit terminates process and returns succeeded")
    func politeQuitSucceeds() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 1234, bundleID: "com.example.app")
        ])
        let clock = FakeClock()
        let terminator = ProcessTerminator(control: control, clock: clock)

        let outcome = try await terminator.execute(
            .killApp(bundleID: "com.example.app", strategy: .politeQuit, force: false)
        )

        #expect(outcome == .succeeded)
        #expect(control.terminateCalls.count == 1)
        #expect(control.terminateCalls.first?.strategy == .politeQuit)
        #expect(await control.isAlive(pid: 1234) == false)
    }

    // MARK: - Target resolution

    @Test("unresolvable bundle ID returns refused with no matching process")
    func unresolvableBundleID() async throws {
        let control = ScriptedProcessControl()
        let terminator = ProcessTerminator(control: control, clock: FakeClock())

        let outcome = try await terminator.execute(
            .killApp(bundleID: "com.ghost", strategy: .politeQuit, force: false)
        )

        #expect(outcome == .refused(reason: "no matching process"))
    }

    // MARK: - Safety rail: SIP / protected

    @Test("protected pid returns notPermitted")
    func protectedPIDNotPermitted() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 50, bundleID: "com.apple.system", isProtected: true)
        ])
        let terminator = ProcessTerminator(control: control, clock: FakeClock())

        let outcome = try await terminator.execute(
            .killApp(bundleID: "com.apple.system", strategy: .politeQuit, force: false)
        )

        #expect(outcome == .notPermitted(reason: "protected process"))
        #expect(control.terminateCalls.isEmpty)
    }

    // MARK: - Safety rail: unsaved changes

    @Test("unsaved changes on frontmost with non-force strategy is refused")
    func unsavedChangesRefused() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 7, bundleID: "com.editor", isFrontmost: true, hasUnsavedChanges: true)
        ])
        let terminator = ProcessTerminator(control: control, clock: FakeClock())

        let outcome = try await terminator.execute(
            .killApp(bundleID: "com.editor", strategy: .politeQuit, force: false)
        )

        #expect(outcome == .refused(reason: "unsaved changes"))
        #expect(control.terminateCalls.isEmpty)
    }

    @Test("unsaved changes with forceQuit strategy bypasses unsaved rail")
    func unsavedChangesForceStrategyProceeds() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 7, bundleID: "com.editor", isFrontmost: true, hasUnsavedChanges: true)
        ])
        let terminator = ProcessTerminator(control: control, clock: FakeClock())

        let outcome = try await terminator.execute(
            .killApp(bundleID: "com.editor", strategy: .forceQuit, force: true)
        )

        #expect(outcome == .succeeded)
        #expect(control.terminateCalls.first?.strategy == .forceQuit)
    }

    // MARK: - Safety rail: cooldown

    @Test("second kill within cooldown window is refused")
    func cooldownBlocksSecondKill() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 1, bundleID: "com.a"),
            .init(pid: 2, bundleID: "com.a")
        ])
        let clock = FakeClock()
        let terminator = ProcessTerminator(
            control: control,
            clock: clock,
            config: TerminatorConfig(cooldown: 60)
        )

        let first = try await terminator.execute(
            .killApp(bundleID: "com.a", strategy: .politeQuit, force: false)
        )
        #expect(first == .succeeded)

        clock.advance(30) // inside 60 s window

        let second = try await terminator.execute(
            .killApp(bundleID: "com.a", strategy: .politeQuit, force: false)
        )
        #expect(second == .refused(reason: "cooldown"))
    }

    @Test("cooldown passes once the configured window has elapsed")
    func cooldownExpires() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 1, bundleID: "com.a"),
            .init(pid: 2, bundleID: "com.a")
        ])
        let clock = FakeClock()
        let terminator = ProcessTerminator(
            control: control,
            clock: clock,
            config: TerminatorConfig(cooldown: 60)
        )

        _ = try await terminator.execute(
            .killApp(bundleID: "com.a", strategy: .politeQuit, force: false)
        )

        clock.advance(61) // past the window

        let second = try await terminator.execute(
            .killApp(bundleID: "com.a", strategy: .politeQuit, force: false)
        )
        #expect(second == .succeeded)
    }

    @Test("cooldown below 30 s floor is clamped up")
    func cooldownClampedToFloor() async throws {
        let config = TerminatorConfig(cooldown: 5, minCooldown: 30)
        #expect(config.effectiveCooldown == 30)

        let control = ScriptedProcessControl([
            .init(pid: 1, bundleID: "com.a"),
            .init(pid: 2, bundleID: "com.a")
        ])
        let clock = FakeClock()
        let terminator = ProcessTerminator(control: control, clock: clock, config: config)

        _ = try await terminator.execute(
            .killApp(bundleID: "com.a", strategy: .politeQuit, force: false)
        )

        // 10 s later would pass the requested 5 s window, but 30 s is the floor.
        clock.advance(10)

        let second = try await terminator.execute(
            .killApp(bundleID: "com.a", strategy: .politeQuit, force: false)
        )
        #expect(second == .refused(reason: "cooldown"))
    }

    // MARK: - Safety rail: global kill switch

    @Test("global kill switch off refuses every request")
    func globalKillSwitchBlocks() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 1, bundleID: "com.a")
        ])
        let terminator = ProcessTerminator(
            control: control,
            clock: FakeClock(),
            config: TerminatorConfig(actionsEnabled: false)
        )

        let outcome = try await terminator.execute(
            .killApp(bundleID: "com.a", strategy: .politeQuit, force: false)
        )
        #expect(outcome == .refused(reason: "global kill switch"))
        #expect(control.terminateCalls.isEmpty)
    }

    @Test("flipping kill switch back on permits subsequent requests")
    func globalKillSwitchToggle() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 1, bundleID: "com.a")
        ])
        let terminator = ProcessTerminator(
            control: control,
            clock: FakeClock(),
            config: TerminatorConfig(actionsEnabled: false)
        )

        let blocked = try await terminator.execute(
            .killApp(bundleID: "com.a", strategy: .politeQuit, force: false)
        )
        #expect(blocked == .refused(reason: "global kill switch"))

        terminator.setActionsEnabled(true)
        let allowed = try await terminator.execute(
            .killApp(bundleID: "com.a", strategy: .politeQuit, force: false)
        )
        #expect(allowed == .succeeded)
    }

    // MARK: - Escalation

    @Test("polite strategy fails with force=true escalates to forceQuit")
    func escalationForceTerminates() async throws {
        // Polite quit scripted to fail; force quit succeeds.
        let control = ScriptedProcessControl([
            .init(
                pid: 99,
                bundleID: "com.stubborn",
                failingStrategies: [.politeQuit]
            )
        ])
        let clock = FakeClock()
        let terminator = ProcessTerminator(
            control: control,
            clock: clock,
            // Zero grace + poll so the test completes immediately. Time is
            // driven by the fake clock — no wall-clock waiting.
            config: TerminatorConfig(graceSeconds: 0, pollInterval: 0.001)
        )

        let outcome = try await terminator.execute(
            .killApp(bundleID: "com.stubborn", strategy: .politeQuit, force: true)
        )

        #expect(outcome == .escalated(previous: "politeQuit"))
        let strategies = control.terminateCalls.map(\.strategy)
        #expect(strategies == [.politeQuit, .forceQuit])
        #expect(await control.isAlive(pid: 99) == false)
    }

    @Test("polite strategy fails without force=true does not escalate")
    func noEscalationWithoutForce() async throws {
        let control = ScriptedProcessControl([
            .init(
                pid: 99,
                bundleID: "com.stubborn",
                failingStrategies: [.politeQuit]
            )
        ])
        let terminator = ProcessTerminator(
            control: control,
            clock: FakeClock(),
            config: TerminatorConfig(graceSeconds: 0, pollInterval: 0.001)
        )

        let outcome = try await terminator.execute(
            .killApp(bundleID: "com.stubborn", strategy: .politeQuit, force: false)
        )

        #expect(outcome == .refused(reason: "process still alive"))
        #expect(control.terminateCalls.map(\.strategy) == [.politeQuit])
        #expect(await control.isAlive(pid: 99) == true)
    }

    // MARK: - Concurrency

    @Test("concurrent execute calls on same target — one succeeds, other refused as cooldown")
    func concurrentCallsSerialize() async throws {
        // First call suspends inside the grace-period loop (polite fails), so
        // while it sleeps the actor can service the second call which should
        // see inFlight and refuse with "cooldown".
        let control = ScriptedProcessControl([
            .init(
                pid: 42,
                bundleID: "com.busy",
                failingStrategies: [.politeQuit]
            )
        ])
        let terminator = ProcessTerminator(
            control: control,
            clock: FakeClock(),
            // Non-zero grace + long poll so the first call is guaranteed to
            // suspend and let the second in. Force=true ensures it eventually
            // escalates and returns a terminal outcome.
            config: TerminatorConfig(graceSeconds: 0.2, pollInterval: 0.05)
        )

        async let first = terminator.execute(
            .killApp(bundleID: "com.busy", strategy: .politeQuit, force: true)
        )
        // Give the first call a beat to enter the actor, mark inFlight, and
        // start awaiting Task.sleep in the grace loop.
        try await Task.sleep(nanoseconds: 20_000_000)
        async let second = terminator.execute(
            .killApp(bundleID: "com.busy", strategy: .politeQuit, force: false)
        )

        let (a, b) = try await (first, second)
        #expect(a == .escalated(previous: "politeQuit"))
        #expect(b == .refused(reason: "cooldown"))
    }

    // MARK: - Non-kill actions

    @Test("non-kill actions are refused by this executor")
    func nonKillActionsRefused() async throws {
        let control = ScriptedProcessControl()
        let terminator = ProcessTerminator(control: control, clock: FakeClock())

        let outcome = try await terminator.execute(.logMessage("hello"))
        #expect(outcome == .refused(reason: "not handled by this executor"))
    }

    // MARK: - Pid-target kill path (PRD-10)

    @Test("killProcess by pid politeQuits the process")
    func killProcessByPidSucceeds() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 4242, bundleID: "com.example.app")
        ])
        let terminator = ProcessTerminator(control: control, clock: FakeClock())

        let outcome = await terminator.killProcess(pid: 4242, strategy: .politeQuit, force: false)

        #expect(outcome == .succeeded)
        #expect(control.terminateCalls.count == 1)
        #expect(control.terminateCalls.first?.pid == 4242)
        #expect(await control.isAlive(pid: 4242) == false)
    }

    @Test("killProcess honours the global kill switch")
    func killProcessRespectsGlobalSwitch() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 11, bundleID: "com.a")
        ])
        let terminator = ProcessTerminator(
            control: control,
            clock: FakeClock(),
            config: TerminatorConfig(actionsEnabled: false)
        )

        let outcome = await terminator.killProcess(pid: 11, strategy: .politeQuit, force: false)

        #expect(outcome == .refused(reason: "global kill switch"))
        #expect(control.terminateCalls.isEmpty)
    }

    @Test("killProcess refuses protected pid with notPermitted")
    func killProcessProtected() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 50, bundleID: "com.apple.system", isProtected: true)
        ])
        let terminator = ProcessTerminator(control: control, clock: FakeClock())

        let outcome = await terminator.killProcess(pid: 50, strategy: .politeQuit, force: false)

        #expect(outcome == .notPermitted(reason: "protected process"))
        #expect(control.terminateCalls.isEmpty)
    }

    @Test("killProcess refuses unsaved changes on non-force strategy")
    func killProcessUnsavedRefused() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 7, bundleID: "com.editor", hasUnsavedChanges: true)
        ])
        let terminator = ProcessTerminator(control: control, clock: FakeClock())

        let outcome = await terminator.killProcess(pid: 7, strategy: .politeQuit, force: false)

        #expect(outcome == .refused(reason: "unsaved changes"))
        #expect(control.terminateCalls.isEmpty)
    }

    @Test("killProcess cooldown is keyed per-pid")
    func killProcessCooldownPerPid() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 1, bundleID: "com.a"),
            .init(pid: 2, bundleID: "com.a")
        ])
        let clock = FakeClock()
        let terminator = ProcessTerminator(
            control: control,
            clock: clock,
            config: TerminatorConfig(cooldown: 60)
        )

        let first = await terminator.killProcess(pid: 1, strategy: .politeQuit, force: false)
        #expect(first == .succeeded)

        clock.advance(10) // inside cooldown

        // Same pid → refused by cooldown.
        let sameAgain = await terminator.killProcess(pid: 1, strategy: .politeQuit, force: false)
        #expect(sameAgain == .refused(reason: "cooldown"))

        // Different pid → independent bucket, allowed.
        let differentPid = await terminator.killProcess(pid: 2, strategy: .politeQuit, force: false)
        #expect(differentPid == .succeeded)
    }

    @Test("killProcess escalates to forceQuit when force=true and polite fails")
    func killProcessEscalates() async throws {
        let control = ScriptedProcessControl([
            .init(pid: 99, bundleID: "com.stubborn", failingStrategies: [.politeQuit])
        ])
        let terminator = ProcessTerminator(
            control: control,
            clock: FakeClock(),
            config: TerminatorConfig(graceSeconds: 0, pollInterval: 0.001)
        )

        let outcome = await terminator.killProcess(pid: 99, strategy: .politeQuit, force: true)

        #expect(outcome == .escalated(previous: "politeQuit"))
        #expect(control.terminateCalls.map(\.strategy) == [.politeQuit, .forceQuit])
        #expect(await control.isAlive(pid: 99) == false)
    }

    @Test("killProcess on a dead / unknown pid returns no-matching-process")
    func killProcessUnknownPid() async throws {
        let control = ScriptedProcessControl()
        let terminator = ProcessTerminator(control: control, clock: FakeClock())

        let outcome = await terminator.killProcess(pid: 9999, strategy: .politeQuit, force: false)

        #expect(outcome == .refused(reason: "no matching process"))
        #expect(control.terminateCalls.isEmpty)
    }
}
