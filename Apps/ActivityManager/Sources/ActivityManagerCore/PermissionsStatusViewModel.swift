import Foundation
import ActivityCapture

public struct PermissionRow: Identifiable, Sendable {
    public enum State: Sendable { case granted, denied, notDetermined }
    public let id: String
    public let title: String
    public let explanation: String
    public let settingsURL: String
    public var state: State

    public init(id: String, title: String, explanation: String, settingsURL: String, state: State) {
        self.id = id
        self.title = title
        self.explanation = explanation
        self.settingsURL = settingsURL
        self.state = state
    }
}

@MainActor
@Observable
public final class PermissionsStatusViewModel {
    public private(set) var rows: [PermissionRow] = []

    private let checker: PermissionsChecker

    public init(checker: PermissionsChecker = SystemPermissionsChecker()) {
        self.checker = checker
    }

    public func refresh() {
        rows = [
            row(
                id: "accessibility",
                title: "Accessibility",
                explanation: "Optional. Unlocks window-title capture (per-document activity). Not needed for app-level frontmost tracking.",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                status: checker.status(for: .accessibility)
            ),
            row(
                id: "calendar",
                title: "Calendar",
                explanation: "Correlates meetings with activity so you can ask \"what was I doing during the design review?\".",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
                status: checker.status(for: .calendar)
            ),
            row(
                id: "focus",
                title: "Focus Status",
                explanation: "Tags sessions with your current Focus mode.",
                settingsURL: "x-apple.systempreferences:com.apple.preference.notifications",
                status: checker.status(for: .focus)
            ),
        ]
    }

    public func openSettings(for rowID: String) {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        switch rowID {
        case "accessibility": checker.openSettings(for: .accessibility)
        case "calendar":      checker.openSettings(for: .calendar)
        case "focus":         checker.openSettings(for: .focus)
        default:              _ = row.settingsURL
        }
    }

    private func row(id: String, title: String, explanation: String, settingsURL: String, status: PermissionStatus) -> PermissionRow {
        PermissionRow(
            id: id,
            title: title,
            explanation: explanation,
            settingsURL: settingsURL,
            state: Self.map(status)
        )
    }

    private static func map(_ status: PermissionStatus) -> PermissionRow.State {
        switch status {
        case .granted: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        }
    }
}
