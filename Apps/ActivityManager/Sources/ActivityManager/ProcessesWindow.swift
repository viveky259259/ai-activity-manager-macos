import SwiftUI
import ActivityManagerCore

/// Activity-Monitor-style Processes pane, embedded into the main window's
/// detail area.
struct ProcessesView: View {
    let deps: AppDependencies
    @State private var viewModel = RunningProcessesViewModel()
    @State private var sortOrder: [KeyPathComparator<SystemProcess>] = [
        .init(\.cpuPercent, order: .reverse)
    ]
    @State private var selection: Int32?
    @State private var showingForceConfirm: Bool = false

    private static let refreshInterval: Duration = .seconds(2)

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.lg)
                .padding(.bottom, DS.Space.md)

            Divider()

            table

            Divider()

            footer
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.sm)
        }
        .dsAmbientBackground()
        .task { await driveRefreshLoop() }
        .alert("Force quit process?", isPresented: $showingForceConfirm) {
            Button("Force Quit", role: .destructive) { performQuit(force: true) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Force quitting sends SIGKILL and can cause data loss.")
        }
    }

    // MARK: - Header

    private var header: some View {
        DSSectionHeader(
            "Processes",
            subtitle: viewModel.isKillSwitchEngaged
                ? "Actions disabled — enable in Settings to quit"
                : "Live system-wide activity, refreshed every 2 seconds"
        ) {
            HStack(spacing: DS.Space.sm) {
                TextField("Filter", text: $viewModel.searchText, prompt: Text("Name, bundle ID, PID, user"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .accessibilityLabel("Filter processes")

                Button {
                    performQuit(force: false)
                } label: {
                    Label("Quit", systemImage: "xmark.circle")
                }
                .disabled(!canQuitSelection)
                .help("Send SIGTERM to the selected process")

                Button {
                    showingForceConfirm = true
                } label: {
                    Label("Force", systemImage: "bolt.slash.fill")
                }
                .disabled(!canQuitSelection)
                .help("Send SIGKILL to the selected process")

                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh now")
                .accessibilityLabel("Refresh processes")
            }
        }
    }

    // MARK: - Table

    private var table: some View {
        Table(sortedRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("PID", value: \.id) { row in
                Text(String(row.id)).monospacedDigit().font(.caption)
            }
            .width(min: 60, ideal: 70, max: 90)

            TableColumn("Name", value: \.name) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.callout)
                    if let bid = row.bundleID, !bid.isEmpty {
                        Text(bid)
                            .font(.caption2.monospaced())
                            .foregroundStyle(DS.Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            TableColumn("% CPU", value: \.cpuPercent) { row in
                if row.isRestricted {
                    Text("—")
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.textTertiary)
                        .help("Task-read permission denied for this process")
                } else {
                    Text(String(format: "%.1f", row.cpuPercent))
                        .monospacedDigit()
                        .foregroundStyle(row.cpuPercent > 50 ? DS.Palette.danger : DS.Palette.textPrimary)
                }
            }
            .width(min: 60, ideal: 75, max: 95)

            TableColumn("Memory", value: \.memoryBytes) { row in
                if row.memoryBytes == 0 && row.isRestricted {
                    Text("—")
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.textTertiary)
                        .help("Memory not available for this process")
                } else {
                    Text(Self.formatBytes(row.memoryBytes))
                        .monospacedDigit()
                        .foregroundStyle(row.isRestricted ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                        .help(row.isRestricted ? "Memory sourced from top (restricted process)" : "")
                }
            }
            .width(min: 80, ideal: 100, max: 130)

            TableColumn("Threads", value: \.threads) { row in
                if row.isRestricted {
                    Text("—").monospacedDigit().foregroundStyle(DS.Palette.textTertiary)
                } else {
                    Text(String(row.threads)).monospacedDigit()
                }
            }
            .width(min: 50, ideal: 65, max: 85)

            TableColumn("User", value: \.user) { row in
                Text(row.user).font(.caption)
            }
            .width(min: 80, ideal: 110, max: 180)
        }
    }

    private var sortedRows: [SystemProcess] {
        viewModel.filtered.sorted(using: sortOrder)
    }

    // MARK: - Footer

    private var footer: some View {
        let t = viewModel.totals
        let restrictedCount = viewModel.filtered.lazy.filter(\.isRestricted).count
        return HStack(spacing: DS.Space.md) {
            Text("\(t.visible) of \(t.total) processes")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Divider().frame(height: 12)
            Text("CPU: \(String(format: "%.1f", t.totalCPU))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(DS.Palette.textSecondary)
            Divider().frame(height: 12)
            Text(Self.memoryFooterText(t))
                .font(.caption.monospacedDigit())
                .foregroundStyle(DS.Palette.textSecondary)
                .help("Memory Used = App + Wired + Compressed (from host_statistics64), matching Activity Monitor.")
            if restrictedCount > 0 {
                Divider().frame(height: 12)
                DSPill(
                    "\(restrictedCount) system",
                    symbol: "gearshape.2.fill",
                    kind: .info
                )
                .help("\(restrictedCount) system process\(restrictedCount == 1 ? "" : "es") owned by root or other users. Memory is sourced from /usr/bin/top; CPU and threads require task-read entitlements and show as —.")
            }
            Spacer()
            if viewModel.isKillSwitchEngaged {
                DSPill("Actions off", symbol: "hand.raised.fill", kind: .warning)
            }
        }
    }

    // MARK: - Actions

    private var canQuitSelection: Bool {
        selection != nil && !viewModel.isKillSwitchEngaged
    }

    private func performQuit(force: Bool) {
        guard let pid = selection else { return }
        _ = viewModel.quit(pid: pid, force: force)
        viewModel.refresh()
    }

    private func driveRefreshLoop() async {
        viewModel.isKillSwitchEngaged = !deps.actions.actionsEnabled
        viewModel.refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.refreshInterval)
            viewModel.isKillSwitchEngaged = !deps.actions.actionsEnabled
            viewModel.refresh()
        }
    }

    // MARK: - Formatting

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.includesUnit = true
        return f
    }()

    private static func formatBytes(_ bytes: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(bytes))
    }

    private static func memoryFooterText(_ t: RunningProcessesViewModel.Totals) -> String {
        guard let used = t.systemMemoryUsedBytes else { return "Memory: —" }
        if let total = t.systemMemoryTotalBytes, total > 0 {
            return "Memory: \(formatBytes(used)) of \(formatBytes(total))"
        }
        return "Memory: \(formatBytes(used))"
    }
}
