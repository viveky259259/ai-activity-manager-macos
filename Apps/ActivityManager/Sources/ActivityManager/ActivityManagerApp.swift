import SwiftUI
import ActivityManagerCore

@main
struct ActivityManagerApp: App {
    @State private var deps: AppDependencies

    init() {
        let d = AppDependencies()
        _deps = State(initialValue: d)
        let persisted = SettingsViewModel(defaults: .standard).provider
        d.setLLMProvider(persisted)
        Task { @MainActor in
            await d.bootstrap()
        }
    }

    var body: some Scene {
        MenuBarExtra("Activity", systemImage: "chart.line.uptrend.xyaxis") {
            MenuBarContent(deps: deps)
        }
        .menuBarExtraStyle(.window)

        Window("ActivityManager", id: "main") {
            MainWindow(deps: deps)
        }
        .defaultSize(width: 1040, height: 680)
    }
}
