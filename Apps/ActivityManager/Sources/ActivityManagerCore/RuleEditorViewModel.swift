import Foundation
import ActivityCore

/// View-model for the rule editor: takes a natural-language description,
/// compiles it via the LLM, lets the user review the compiled DSL, then saves
/// it as a dry-run rule in the store.
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

    private let llm: any LLMProvider
    private let store: any ActivityStore

    public init(llm: any LLMProvider, store: any ActivityStore) {
        self.llm = llm
        self.store = store
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

    /// Persists a stub rule referencing the compiled DSL in dry-run mode.
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
        } catch {
            self.errorMessage = String(describing: error)
        }
    }
}
