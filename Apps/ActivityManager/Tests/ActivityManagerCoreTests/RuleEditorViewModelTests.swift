import Foundation
import Testing
import ActivityCore
import ActivityCoreTestSupport
@testable import ActivityManagerCore

@Suite
@MainActor
struct RuleEditorViewModelTests {

    private func makeViewModel() -> (RuleEditorViewModel, FakeStore, FakeLLMProvider) {
        let store = FakeStore()
        let llm = FakeLLMProvider()
        let viewModel = RuleEditorViewModel(llm: llm, store: store)
        return (viewModel, store, llm)
    }

    // MARK: - loadRules

    @Test("loadRules populates the rules array sorted newest-first")
    func loadRulesSortsNewestFirst() async throws {
        let (viewModel, store, _) = makeViewModel()
        let older = Rule(
            name: "older",
            nlSource: "older",
            trigger: .idleEnded,
            actions: [.logMessage("a")],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = Rule(
            name: "newer",
            nlSource: "newer",
            trigger: .idleEnded,
            actions: [.logMessage("b")],
            createdAt: Date(timeIntervalSince1970: 1_700_000_500),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        try await store.upsertRule(older)
        try await store.upsertRule(newer)

        await viewModel.loadRules()

        #expect(viewModel.rules.count == 2)
        #expect(viewModel.rules.first?.name == "newer")
        #expect(viewModel.rules.last?.name == "older")
        #expect(!viewModel.isLoadingRules)
    }

    @Test("loadRules on empty store yields empty array")
    func loadRulesEmpty() async {
        let (viewModel, _, _) = makeViewModel()
        await viewModel.loadRules()
        #expect(viewModel.rules.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - save

    @Test("save persists the rule and refreshes the local list")
    func saveRefreshesList() async {
        let (viewModel, store, llm) = makeViewModel()
        llm.stubText("{\"trigger\":{\"type\":\"idleEnded\"}}")

        viewModel.naturalLanguage = "When I come back from idle"
        await viewModel.compile()
        await viewModel.save()

        let stored = try? await store.rules()
        #expect(stored?.count == 1)
        #expect(viewModel.rules.count == 1)
        #expect(viewModel.rules.first?.name == "When I come back from idle")
        #expect(viewModel.lastSavedRuleID != nil)
    }

    // MARK: - deleteRule

    @Test("deleteRule removes the rule and refreshes the list")
    func deleteRemovesAndRefreshes() async throws {
        let (viewModel, store, _) = makeViewModel()
        let rule = Rule(
            name: "to delete",
            nlSource: "x",
            trigger: .idleEnded,
            actions: [.logMessage("x")],
            createdAt: Date(),
            updatedAt: Date()
        )
        try await store.upsertRule(rule)
        await viewModel.loadRules()
        #expect(viewModel.rules.count == 1)

        await viewModel.deleteRule(id: rule.id)

        #expect(viewModel.rules.isEmpty)
        let stored = try? await store.rules()
        #expect(stored?.isEmpty == true)
    }
}
