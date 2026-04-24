import SwiftUI
import ActivityManagerCore

struct SettingsView: View {
    let deps: AppDependencies
    @State private var viewModel = SettingsViewModel(defaults: .standard)
    @State private var permissions = PermissionsStatusViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                DSSectionHeader(
                    "Settings",
                    subtitle: "Privacy-safe controls — everything is local unless you opt in"
                )

                actionsSection
                retentionSection
                llmSection
                permissionsSection
                storageSection
            }
            .padding(DS.Space.lg)
        }
        .dsAmbientBackground()
        .task {
            permissions.refresh()
            deps.setActionsEnabled(viewModel.actionsEnabled)
            deps.setLLMProvider(viewModel.provider)
            viewModel.onActionsEnabledChange = { [deps] enabled in
                deps.setActionsEnabled(enabled)
            }
            viewModel.onProviderChange = { [deps] choice in
                Task { @MainActor in deps.setLLMProvider(choice) }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Actions")
                            .font(.headline)
                        Text("Master kill switch for rule-driven app termination and Focus changes.")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.actionsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("Actions enabled")
                }

                Divider()

                HStack(spacing: DS.Space.sm) {
                    Image(systemName: viewModel.actionsEnabled ? "checkmark.circle.fill" : "hand.raised.fill")
                        .foregroundStyle(viewModel.actionsEnabled ? DS.Palette.success : DS.Palette.warning)
                    Text(viewModel.actionsEnabled
                         ? "Rules can terminate apps and change Focus mode."
                         : "Global kill switch engaged — no actions will fire.")
                        .font(.callout)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Retention

    private var retentionSection: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Retention")
                    .font(.headline)
                Text("How long to keep captured events on disk.")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                Divider()
                Stepper(
                    value: Binding(
                        get: { viewModel.retentionDays },
                        set: { viewModel.setRetentionDays($0) }
                    ),
                    in: 1...365
                ) {
                    HStack {
                        Text("Keep events for")
                            .font(.callout)
                        Text("\(viewModel.retentionDays) day\(viewModel.retentionDays == 1 ? "" : "s")")
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - LLM provider

    private var llmSection: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("LLM provider")
                    .font(.headline)
                Text("Anthropic uses the cloud with redaction. Local runs on-device via Apple Foundation Models. None disables NL features.")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                Divider()
                Picker("Provider", selection: $viewModel.provider) {
                    ForEach(SettingsViewModel.ProviderChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack {
                    Text("Permissions")
                        .font(.headline)
                    Spacer()
                    Button {
                        permissions.refresh()
                    } label: {
                        Label("Re-check", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("Frontmost-app tracking works without prompts. The others unlock optional capture sources when their features ship.")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSecondary)

                Divider()

                if permissions.rows.isEmpty {
                    HStack(spacing: DS.Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                            .font(.callout)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                } else {
                    VStack(spacing: DS.Space.sm) {
                        ForEach(permissions.rows) { row in
                            PermissionRowView(row: row) {
                                permissions.openSettings(for: row.id)
                            }
                            if row.id != permissions.rows.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Storage")
                    .font(.headline)
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Label("Database", systemImage: "internaldrive")
                        .font(.callout)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                    Text(AppDependencies.defaultStoreURL().path)
                        .font(.caption.monospaced())
                        .foregroundStyle(DS.Palette.textTertiary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: 420, alignment: .trailing)
                }
            }
        }
    }
}

private struct PermissionRowView: View {
    let row: PermissionRow
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(row.title).font(.callout.weight(.medium))
                    Spacer()
                    DSPill(statusLabel, kind: pillKind)
                }
                Text(row.explanation)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                onOpen()
            } label: {
                Label("Open Settings", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Open System Settings for \(row.title)")
        }
        .padding(.vertical, DS.Space.xs)
    }

    private var statusIcon: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconTint)
            .font(.title3)
            .frame(width: 22)
    }

    private var iconName: String {
        switch row.state {
        case .granted: return "checkmark.seal.fill"
        case .denied: return "xmark.octagon.fill"
        case .notDetermined: return "questionmark.circle"
        }
    }

    private var iconTint: Color {
        switch row.state {
        case .granted: return DS.Palette.success
        case .denied: return DS.Palette.danger
        case .notDetermined: return DS.Palette.warning
        }
    }

    private var statusLabel: String {
        switch row.state {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not determined"
        }
    }

    private var pillKind: DSPill.Kind {
        switch row.state {
        case .granted: return .success
        case .denied: return .danger
        case .notDetermined: return .warning
        }
    }
}
