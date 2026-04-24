import Foundation
import os
#if canImport(AppKit)
import AppKit
#endif
#if canImport(ApplicationServices)
import ApplicationServices
#endif
#if canImport(EventKit)
import EventKit
#endif
#if canImport(Intents)
import Intents
#endif

public enum Permission: Hashable, Sendable {
    case accessibility
    case calendar
    case focus
    case automation(bundleID: String)
}

public enum PermissionStatus: String, Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}

public protocol PermissionsChecker: Sendable {
    func status(for permission: Permission) -> PermissionStatus
    func openSettings(for permission: Permission)
}

/// Live checker that asks the real macOS APIs. Intentionally conservative:
/// for statuses that macOS does not expose synchronously, returns `.notDetermined`
/// so callers can kick off an explicit permission request flow.
public struct SystemPermissionsChecker: PermissionsChecker {
    public init() {}

    public func status(for permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            #if canImport(ApplicationServices)
            return AXIsProcessTrusted() ? .granted : .denied
            #else
            return .notDetermined
            #endif

        case .calendar:
            #if canImport(EventKit)
            let status: EKAuthorizationStatus
            if #available(macOS 14, *) {
                status = EKEventStore.authorizationStatus(for: .event)
            } else {
                status = EKEventStore.authorizationStatus(for: .event)
            }
            switch status {
            case .authorized: return .granted
            case .fullAccess: return .granted
            case .writeOnly: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
            #else
            return .notDetermined
            #endif

        case .focus:
            #if canImport(Intents)
            let s = INFocusStatusCenter.default.authorizationStatus
            switch s {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
            #else
            return .notDetermined
            #endif

        case .automation:
            // Automation (AppleEvents) permission cannot be introspected
            // without triggering a prompt. Treat as not-determined.
            return .notDetermined
        }
    }

    public func openSettings(for permission: Permission) {
        #if canImport(AppKit)
        let url: URL? = {
            switch permission {
            case .accessibility:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            case .calendar:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
            case .focus:
                return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
            case .automation:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
            }
        }()
        if let url {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

/// Test double: returns scripted statuses and records `openSettings` calls.
public final class FakePermissionsChecker: PermissionsChecker, @unchecked Sendable {
    private struct State {
        var statuses: [Permission: PermissionStatus] = [:]
        var opened: [Permission] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(initial: [Permission: PermissionStatus] = [:]) {
        state.withLock { $0.statuses = initial }
    }

    public func setStatus(_ status: PermissionStatus, for permission: Permission) {
        state.withLock { $0.statuses[permission] = status }
    }

    public var openedPermissions: [Permission] {
        state.withLock { $0.opened }
    }

    public func status(for permission: Permission) -> PermissionStatus {
        state.withLock { $0.statuses[permission] ?? .notDetermined }
    }

    public func openSettings(for permission: Permission) {
        state.withLock { $0.opened.append(permission) }
    }
}
