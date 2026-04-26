import Foundation
import ActivityCore

/// View-model for the rule editor: takes a natural-language description,
/// compiles it via the LLM, lets the user review the compiled DSL, then saves
/// it as a dry-run rule in the store. Also exposes the list of saved rules so
/// the editor surface can render them above the form.
@MainActor
@Observable
public final class RuleEditorViewModel {
    public var naturalLanguage: String = ""
    public var compiledDSL: String = ""
    public var isCompiling: Bool = false
    public var isSaving: Bool = false
    public var isDryRun: Bool = true
    public var errorMessage: String?
    public var lastSavedRuleID: UUID?

    public var rules: [Rule] = []
    public var isLoadingRules: Bool = false

    private let llm: any LLMProvider
    private let store: any ActivityStore

    public init(llm: any LLMProvider, store: any ActivityStore) {
        self.llm = llm
        self.store = store
    }

    /// Fetches every saved rule from the store, sorted newest-first.
    public func loadRules() async {
        isLoadingRules = true
        defer { isLoadingRules = false }
        do {
            let fetched = try await store.rules()
            self.rules = fetched.sorted { $0.createdAt > $1.createdAt }
        } catch {
            self.errorMessage = String(describing: error)
        }
    }

    /// Removes a rule by ID and refreshes the local list.
    public func deleteRule(id: UUID) async {
        do {
            try await store.deleteRule(id: id)
            await loadRules()
        } catch {
            self.errorMessage = String(describing: error)
        }
    }

    /// Calls the LLM with the current `naturalLanguage` and stores the raw
    /// response text as `compiledDSL`. The real app will post-process this
    /// into a `Rule` via a dedicated use-case; for scaffolding we just surface
    /// the text.
    public func compile() async {
        let nl = naturalLanguage
        guard !nl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Natural language is empty"
            return
        }
        isCompiling = true
        errorMessage = nil
        defer { isCompiling = false }

        let request = LLMRequest(
            system: "Compile the user's rule description into the ActivityManager DSL JSON.",
            user: nl,
            responseFormat: .json(schema: nil)
        )
        do {
            let response = try await llm.complete(request)
            self.compiledDSL = response.text
        } catch {
            self.errorMessage = String(describing: error)
        }
    }

    /// Persists a stub rule referencing the compiled DSL in dry-run mode, then
    /// refreshes the saved-rules list so the UI reflects the new entry.
    public func save() async {
        guard !compiledDSL.isEmpty else {
            errorMessage = "Compile a rule before saving"
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let now = Date()
        let rule = Rule(
            name: naturalLanguage.isEmpty ? "Untitled rule" : naturalLanguage,
            nlSource: naturalLanguage,
            trigger: .appFocused(bundleID: "unknown", durationAtLeast: nil),
            actions: [.logMessage(compiledDSL)],
            mode: isDryRun ? .dryRun : .active,
            createdAt: now,
            updatedAt: now
        )
        do {
            try await store.upsertRule(rule)
            self.lastSavedRuleID = rule.id
            await loadRules()
        } catch {
            self.errorMessage = String(describing: error)
        }
    }
}
