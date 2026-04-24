import Foundation
import Testing
@testable import ActivityManagerCore

@Suite
@MainActor
struct SettingsViewModelTests {
    @Test
    func toggleActionsRoundTrips() {
        let vm = SettingsViewModel(actionsEnabled: true)
        #expect(vm.actionsEnabled == true)
        vm.toggleActions()
        #expect(vm.actionsEnabled == false)
        vm.toggleActions()
        #expect(vm.actionsEnabled == true)
    }

    @Test
    func retentionClampsAtOne() {
        let vm = SettingsViewModel(retentionDays: 30)
        vm.setRetentionDays(0)
        #expect(vm.retentionDays == 1)
        vm.setRetentionDays(-5)
        #expect(vm.retentionDays == 1)
        vm.setRetentionDays(60)
        #expect(vm.retentionDays == 60)
    }

    @Test
    func providerSelectionUpdates() {
        let vm = SettingsViewModel()
        vm.setProvider(.anthropic)
        #expect(vm.provider == .anthropic)
        vm.setProvider(.local)
        #expect(vm.provider == .local)
    }
}
