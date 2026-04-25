import SwiftUI
import ActivityManagerCore

/// First-run walkthrough — 4 panels (Welcome → Permissions → API key →
/// Actions opt-in). Shown once when `onboarding.completed` is absent from
/// UserDefaults; re-runnable from Settings via the "Run walkthrough" button.
struct OnboardingView: View {
    let deps: AppDependencies
    let onClose: () -> Void

    @State private var step: Step = .welcome
    @State private var permissions = PermissionsStatusViewModel()
    @State private var apiKeyDraft: String = ""
    @State private var hasKey: Bool = false
    @State private var actionsOptIn: Bool = false

    enum Step: Int, CaseIterable {
        case welcome, permissions, apiKey, actions

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .permissions: return "Permissions"
            case .apiKey: return "AI provider"
            case .actions: return "Actions"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, DS.Space.lg)
                .padding(.horizontal, DS.Space.lg)

            Group {
                switch step {
                case .welcome:     welcomePane
                case .permissions: permissionsPane
                case .apiKey:      apiKeyPane
                case .actions:     actionsPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(DS.Space.lg)

            Divider()

            HStack {
                if step != .welcome {
                    Button("Back") { advance(by: -1) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                }
                Spacer()
                Button("Skip") { finish() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(step == .actions ? "Get started" : "Continue") {
                    if step == .actions { finish() } else { advance(by: 1) }
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
            .padding(DS.Space.md)
        }
        .frame(width: 580, height: 480)
        .task {
            permissions.refresh()
            hasKey = KeychainStore.read(account: KeychainStore.anthropicAccount)?.isEmpty == false
        }
    }

    // MARK: - Panes

    private var welcomePane: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom))
            Text("Welcome to ActivityManager")
                .font(.title.weight(.semibold))
            Text("Your Mac, finally answerable. Ask any AI assistant — Claude Desktop, Cursor, Zed — what's running and tell it to clean up. All capture stays on this device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.Palette.textSecondary)
                .padding(.horizontal, DS.Space.xl)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                BulletRow(symbol: "lock.fill", text: "Local-first capture. Nothing leaves your Mac unless you opt in.")
                BulletRow(symbol: "bolt.shield.fill", text: "Destructive actions are off by default — you decide when AI can terminate apps.")
                BulletRow(symbol: "chart.line.uptrend.xyaxis", text: "Searchable timeline of what you've been doing, on disk in SQLite.")
            }
            .padding(.top, DS.Space.sm)
        }
    }

    private var permissionsPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Grant the access you want to use")
                .font(.title2.weight(.semibold))
            Text("Frontmost-app capture works without prompts. Grant the others as you need their features.")
                .font(.callout)
                .foregroundStyle(DS.Palette.textSecondary)
            Divider()

            if permissions.rows.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                ForEach(permissions.rows) { row in
                    HStack {
                        Image(systemName: row.state == .granted ? "checkmark.seal.fill" : "circle.dashed")
                            .foregroundStyle(row.state == .granted ? DS.Palette.success : DS.Palette.warning)
                        VStack(alignment: .leading) {
                            Text(row.title).font(.callout.weight(.medium))
                            Text(row.explanation)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textTertiary)
                        }
                        Spacer()
                        Button("Open Settings") {
                            permissions.openSettings(for: row.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Divider()
                }
            }

            HStack {
                Spacer()
                Button {
                    permissions.refresh()
                } label: {
                    Label("Re-check", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var apiKeyPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Optional: bring your own API key")
                .font(.title2.weight(.semibold))
            Text("If you want cloud LLM features (Insights, natural-language rule editing), paste an Anthropic API key. Stored locally in Keychain. You can also skip this — the app works with on-device Apple Foundation Models or no LLM at all.")
                .font(.callout)
                .foregroundStyle(DS.Palette.textSecondary)
            Divider()

            HStack {
                SecureField("sk-ant-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Button("Save") {
                    let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    if KeychainStore.write(trimmed, account: KeychainStore.anthropicAccount) {
                        hasKey = true
                        apiKeyDraft = ""
                    }
                }
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            HStack(spacing: DS.Space.xs) {
                Image(systemName: hasKey ? "checkmark.seal.fill" : "info.circle")
                    .foregroundStyle(hasKey ? DS.Palette.success : DS.Palette.textTertiary)
                Text(hasKey ? "API key saved in Keychain." : "No key saved yet.")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
    }

    private var actionsPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Allow destructive actions?")
                .font(.title2.weight(.semibold))
            Text("Off by default. When on, rules and AI hosts can terminate apps via the same safety rails: SIP-protected processes are blocked, frontmost apps with unsaved changes are spared, and there's a 60-second per-bundle cooldown.")
                .font(.callout)
                .foregroundStyle(DS.Palette.textSecondary)
            Divider()

            Toggle(isOn: $actionsOptIn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable destructive actions")
                        .font(.callout.weight(.medium))
                    Text("You can flip this any time in Settings.")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .toggleStyle(.switch)

            HStack(spacing: DS.Space.xs) {
                Image(systemName: actionsOptIn ? "checkmark.shield.fill" : "hand.raised.fill")
                    .foregroundStyle(actionsOptIn ? DS.Palette.success : DS.Palette.textTertiary)
                Text(actionsOptIn
                     ? "Rules and AI tools may terminate apps."
                     : "Global kill switch engaged — no actions will fire.")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            }
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? DS.Palette.accent : DS.Palette.textTertiary.opacity(0.3))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func advance(by delta: Int) {
        let next = max(0, min(Step.allCases.count - 1, step.rawValue + delta))
        step = Step(rawValue: next) ?? step
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboarding.completed")
        deps.setActionsEnabled(actionsOptIn)
        UserDefaults.standard.set(actionsOptIn, forKey: "settings.actionsEnabled")
        onClose()
    }
}

private struct BulletRow: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: symbol)
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 22)
            Text(text)
                .font(.callout)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }
}
