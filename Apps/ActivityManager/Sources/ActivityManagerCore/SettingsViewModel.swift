import Foundation

/// Settings toggles surfaced on the Settings scene.
///
/// When constructed with a `UserDefaults` (the app-level init does this),
/// changes are persisted and forwarded to the live runtime via the `apply`
/// closures the view installs. Tests use the parameterised init with `defaults: nil`
/// to get pure in-memory behaviour.
@MainActor
@Observable
public final class SettingsViewModel {
    public enum ProviderChoice: String, CaseIterable, Identifiable, Sendable {
        case anthropic
        case local
        case null

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .anthropic: return "Anthropic"
            case .local: return "Local"
            case .null: return "None"
            }
        }
    }

    public var actionsEnabled: Bool {
        didSet {
            defaults?.set(actionsEnabled, forKey: Keys.actionsEnabled)
            onActionsEnabledChange?(actionsEnabled)
        }
    }

    public var provider: ProviderChoice {
        didSet {
            defaults?.set(provider.rawValue, forKey: Keys.provider)
            onProviderChange?(provider)
        }
    }

    public private(set) var retentionDays: Int

    private let defaults: UserDefaults?
    public var onActionsEnabledChange: (@Sendable (Bool) -> Void)?
    public var onProviderChange: (@Sendable (ProviderChoice) -> Void)?

    private enum Keys {
        static let actionsEnabled = "settings.actionsEnabled"
        static let provider = "settings.provider"
        static let retentionDays = "settings.retentionDays"
    }

    /// Test-friendly init — no persistence. Pass values explicitly.
    public init(
        actionsEnabled: Bool = true,
        provider: ProviderChoice = .null,
        retentionDays: Int = 30
    ) {
        self.defaults = nil
        self.actionsEnabled = actionsEnabled
        self.provider = provider
        self.retentionDays = retentionDays
    }

    /// App init — values come from (and persist back to) `UserDefaults`.
    public init(defaults: UserDefaults) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.actionsEnabled) != nil {
            self.actionsEnabled = defaults.bool(forKey: Keys.actionsEnabled)
        } else {
            self.actionsEnabled = true
        }

        if let raw = defaults.string(forKey: Keys.provider),
           let choice = ProviderChoice(rawValue: raw) {
            self.provider = choice
        } else {
            self.provider = .null
        }

        let stored = defaults.integer(forKey: Keys.retentionDays)
        self.retentionDays = stored > 0 ? stored : 30
    }

    public func toggleActions() {
        actionsEnabled.toggle()
    }

    public func setProvider(_ choice: ProviderChoice) {
        self.provider = choice
    }

    public func setRetentionDays(_ days: Int) {
        let clamped = max(1, days)
        retentionDays = clamped
        defaults?.set(clamped, forKey: Keys.retentionDays)
    }
}
