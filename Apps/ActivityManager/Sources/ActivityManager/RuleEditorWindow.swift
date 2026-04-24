import SwiftUI
import ActivityManagerCore

struct RuleEditorView: View {
    let deps: AppDependencies
    @State private var viewModel: RuleEditorViewModel

    init(deps: AppDependencies) {
        self.deps = deps
        _viewModel = State(
            initialValue: RuleEditorViewModel(
                llm: deps.llm.provider(for: .ruleCompilation),
                store: deps.store
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                DSSectionHeader(
                    "Rules",
                    subtitle: "Describe a rule in plain English and compile it to the DSL"
                )

                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("Natural language")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.Palette.textSecondary)
                        TextField(
                            "e.g. Quit Slack if I'm idle for 10 minutes during Focus",
                            text: $viewModel.naturalLanguage,
                            axis: .vertical
                        )
                        .lineLimit(3...8)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Rule description in natural language")

                        HStack(spacing: DS.Space.sm) {
                            Button {
                                Task { await viewModel.compile() }
                            } label: {
                                Label("Compile", systemImage: "wand.and.stars")
                            }
                            .dsPrimaryButtonStyle()
                            .disabled(viewModel.isCompiling || viewModel.naturalLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if viewModel.isCompiling {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                }

                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        HStack {
                            Text("Compiled DSL")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.Palette.textSecondary)
                            Spacer()
                            if !viewModel.compiledDSL.isEmpty {
                                DSPill("ready", symbol: "checkmark.seal.fill", kind: .success)
                            }
                        }

                        if viewModel.compiledDSL.isEmpty {
                            Text("Compile the description above to preview the DSL.")
                                .font(.callout)
                                .foregroundStyle(DS.Palette.textTertiary)
                                .padding(.vertical, DS.Space.md)
                        } else {
                            ScrollView(.vertical) {
                                Text(viewModel.compiledDSL)
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(DS.Space.sm)
                            }
                            .frame(minHeight: 140)
                            .background(DS.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        }

                        Divider()

                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                            Toggle(isOn: $viewModel.isDryRun) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Dry-run mode")
                                        .font(.callout.weight(.medium))
                                    Text(viewModel.isDryRun
                                         ? "Rule will log matches only — no actions fire."
                                         : "Rule will fire its actions when triggered.")
                                        .font(.caption)
                                        .foregroundStyle(DS.Palette.textSecondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .accessibilityLabel("Save rule in dry-run mode")
                            Spacer()
                        }

                        HStack(spacing: DS.Space.sm) {
                            Button {
                                Task { await viewModel.save() }
                            } label: {
                                Label("Save rule", systemImage: "tray.and.arrow.down.fill")
                            }
                            .dsPrimaryButtonStyle()
                            .keyboardShortcut("s", modifiers: [.command])
                            .disabled(viewModel.isSaving || viewModel.compiledDSL.isEmpty)
                            .accessibilityLabel(viewModel.isDryRun ? "Save rule in dry-run mode" : "Save rule as active")

                            if viewModel.isSaving {
                                ProgressView().controlSize(.small)
                            }

                            if let id = viewModel.lastSavedRuleID {
                                DSPill(
                                    "saved \(id.uuidString.prefix(8))",
                                    symbol: "checkmark.circle.fill",
                                    kind: viewModel.isDryRun ? .info : .success
                                )
                            }
                            Spacer()
                        }
                    }
                }

                if let message = viewModel.errorMessage {
                    DSCard {
                        HStack(alignment: .top, spacing: DS.Space.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DS.Palette.danger)
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(DS.Palette.textPrimary)
                            Spacer()
                        }
                    }
                }
            }
            .padding(DS.Space.lg)
        }
        .dsAmbientBackground()
    }
}
