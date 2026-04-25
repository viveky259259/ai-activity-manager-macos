import SwiftUI
import ActivityManagerCore

/// Unified single-window shell. The 4 old scenes (Timeline / Rules / Processes
/// / Settings) are now sidebar sections; Overview and Insights added.
///
/// Rationale (HIG / Apple native apps): macOS utilities favour one primary
/// window with a sidebar + detail pane (Mail, Reminders, Music, System
/// Settings, Activity Monitor with its toolbar tabs). Four separate windows
/// for sibling destinations fragment the experience and fight the WindowGroup
/// state preservation model.
struct MainWindow: View {
    let deps: AppDependencies

    @SceneStorage("MainWindow.section") private var sectionRaw: String = Section.overview.rawValue
    @State private var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "onboarding.completed")

    private var selected: Binding<Section> {
        Binding(
            get: { Section(rawValue: sectionRaw) ?? .overview },
            set: { sectionRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: selected)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail(for: selected.wrappedValue)
                .frame(minWidth: 620, minHeight: 480)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(deps: deps) { showOnboarding = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ActivityManager.runOnboarding"))) { _ in
            showOnboarding = true
        }
    }

    @ViewBuilder
    private func detail(for section: Section) -> some View {
        switch section {
        case .overview:  OverviewView(deps: deps, selection: selected)
        case .processes: ProcessesView(deps: deps)
        case .timeline:  TimelineView(deps: deps)
        case .rules:     RuleEditorView(deps: deps)
        case .insights:  InsightsView(deps: deps)
        case .settings:  SettingsView(deps: deps)
        }
    }
}

enum Section: String, CaseIterable, Identifiable, Hashable {
    case overview, processes, timeline, rules, insights, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:  return "Overview"
        case .processes: return "Processes"
        case .timeline:  return "Timeline"
        case .rules:     return "Rules"
        case .insights:  return "Insights"
        case .settings:  return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview:  return "square.grid.2x2"
        case .processes: return "cpu"
        case .timeline:  return "clock"
        case .rules:     return "slider.horizontal.3"
        case .insights:  return "sparkles"
        case .settings:  return "gear"
        }
    }

    var tint: Color {
        switch self {
        case .overview:  return .accentColor
        case .processes: return .blue
        case .timeline:  return .purple
        case .rules:     return .teal
        case .insights:  return .pink
        case .settings:  return .gray
        }
    }
}

struct SidebarView: View {
    @Binding var selection: Section

    var body: some View {
        List(Section.allCases, selection: $selection) { section in
            NavigationLink(value: section) {
                Label {
                    Text(section.title)
                } icon: {
                    Image(systemName: section.symbol)
                        .foregroundStyle(section.tint)
                }
            }
            .tag(section)
        }
        .navigationTitle("ActivityManager")
        .listStyle(.sidebar)
    }
}
