import Testing
import Foundation
@testable import ActivityCore
import ActivityCoreTestSupport

@Suite("CompileRuleFromNL")
struct CompileRuleFromNLTests {

    let sampleJSON = """
    {
      "name": "Figma focus",
      "trigger": {"appFocused": {"bundleID": "com.figma.Desktop", "durationAtLeast": 1800}},
      "actions": [{"setFocusMode": {"name": "Deep"}}],
      "cooldown": 300
    }
    """

    @Test("Empty NL input throws invalidShape")
    func emptyInput() async {
        let llm = FakeLLMProvider()
        let uc = CompileRuleFromNL(provider: llm, clock: FakeClock())
        do {
            _ = try await uc.compile("   ")
            Issue.record("expected throw")
        } catch let error as CompileRuleFromNL.CompilerError {
            #expect(error == .invalidShape("empty input"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("Happy path produces a dry-run rule")
    func happyPath() async throws {
        let llm = FakeLLMProvider()
        llm.stubJSON(sampleJSON)
        let clock = FakeClock()
        let uc = CompileRuleFromNL(provider: llm, clock: clock)
        let rule = try await uc.compile("when I'm in figma for 30 minutes enable Deep focus")
        #expect(rule.mode == .dryRun)
        #expect(rule.name == "Figma focus")
        #expect(rule.actions.count == 1)
        #expect(rule.cooldown == 300)
        if case .appFocused(let id, let dur) = rule.trigger {
            #expect(id == "com.figma.Desktop")
            #expect(dur == 1800)
        } else {
            Issue.record("wrong trigger")
        }
    }

    @Test("Provider failure surfaces as compilerError")
    func providerFailure() async {
        struct Boom: Error {}
        let llm = FakeLLMProvider()
        llm.stubError(Boom())
        let uc = CompileRuleFromNL(provider: llm, clock: FakeClock())
        do {
            _ = try await uc.compile("something")
            Issue.record("expected throw")
        } catch let error as CompileRuleFromNL.CompilerError {
            if case .providerFailed = error { /* ok */ } else { Issue.record("wrong error: \(error)") }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("Invalid JSON triggers invalidShape")
    func invalidJSON() async {
        let llm = FakeLLMProvider()
        llm.stubText("not json")
        let uc = CompileRuleFromNL(provider: llm, clock: FakeClock())
        do {
            _ = try await uc.compile("x")
            Issue.record("expected throw")
        } catch let error as CompileRuleFromNL.CompilerError {
            if case .invalidShape = error { /* ok */ } else { Issue.record("wrong: \(error)") }
        } catch { Issue.record("unexpected") }
    }

    @Test("Zero actions fails validation")
    func zeroActions() async {
        let bad = """
        {"name":"x","trigger":{"idleEnded":{}},"actions":[]}
        """
        let llm = FakeLLMProvider()
        llm.stubJSON(bad)
        let uc = CompileRuleFromNL(provider: llm, clock: FakeClock())
        do {
            _ = try await uc.compile("x")
            Issue.record("expected throw")
        } catch let error as CompileRuleFromNL.CompilerError {
            if case .invalidShape = error { /* ok */ } else { Issue.record("wrong: \(error)") }
        } catch { Issue.record("unexpected") }
    }

    @Test("Bundle id without dots fails validation")
    func badBundleID() async {
        let bad = """
        {"name":"x","trigger":{"idleEnded":{}},"actions":[{"killApp":{"bundleID":"slack","strategy":"politeQuit","force":false}}]}
        """
        let llm = FakeLLMProvider()
        llm.stubJSON(bad)
        let uc = CompileRuleFromNL(provider: llm, clock: FakeClock())
        do {
            _ = try await uc.compile("x")
            Issue.record("expected throw")
        } catch let error as CompileRuleFromNL.CompilerError {
            if case .invalidShape = error { /* ok */ } else { Issue.record("wrong: \(error)") }
        } catch { Issue.record("unexpected") }
    }
}
