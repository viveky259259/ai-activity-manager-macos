import Foundation
import ActivityCore

/// Live snapshot of what the user is doing right now, derived from the capture
/// event stream. Menu-bar surfaces bind to this.
///
/// Only transitions that are meaningful for the menu bar are reflected:
/// - `.app` → bundle id + localized name
/// - `.idleSpan` → flagged as idle (user away from input)
/// Other event kinds are ignored to keep the display stable.
@MainActor
@Observable
public final class CurrentActivityState {
    public private(set) var bundleID: String?
    public private(set) var name: String?
    public private(set) var isIdle: Bool
    public private(set) var lastChangeAt: Date?
    public private(set) var sampleCount: Int

    public init() {
        self.bundleID = nil
        self.name = nil
        self.isIdle = false
        self.lastChangeAt = nil
        self.sampleCount = 0
    }

    public var display: String {
        if isIdle { return "Idle" }
        if let name, !name.isEmpty { return name }
        if let bundleID, !bundleID.isEmpty { return bundleID }
        return "—"
    }

    public func update(with event: ActivityEvent) {
        sampleCount += 1
        switch event.subject {
        case .app(let id, let n):
            bundleID = id
            name = n
            isIdle = false
            lastChangeAt = event.timestamp
        case .idleSpan:
            isIdle = true
            lastChangeAt = event.timestamp
        default:
            break
        }
    }
}
