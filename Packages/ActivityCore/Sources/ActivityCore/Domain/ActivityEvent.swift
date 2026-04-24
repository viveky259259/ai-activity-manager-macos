import Foundation

public struct ActivityEvent: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let source: Source
    public let subject: Subject
    public let attributes: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        source: Source,
        subject: Subject,
        attributes: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.subject = subject
        self.attributes = attributes
    }

    public enum Source: String, Hashable, Sendable, Codable, CaseIterable {
        case frontmost
        case idle
        case calendar
        case focusMode
        case screenshot
        case rule
        case mcp
        case cli
    }

    public enum Subject: Hashable, Sendable, Codable {
        case app(bundleID: String, name: String)
        case url(host: String, path: String)
        case calendarEvent(id: String, title: String)
        case focusMode(name: String?)
        case idleSpan(startedAt: Date, endedAt: Date)
        case screenshotText(snippet: String)
        case ruleFired(ruleID: UUID, ruleName: String)
        case custom(kind: String, identifier: String)

        public var primaryKey: String {
            switch self {
            case .app(let id, _): return id
            case .url(let host, _): return host
            case .calendarEvent(let id, _): return id
            case .focusMode(let name): return name ?? ""
            case .idleSpan: return "idle"
            case .screenshotText: return "ocr"
            case .ruleFired(let id, _): return id.uuidString
            case .custom(_, let id): return id
            }
        }

        public var kindName: String {
            switch self {
            case .app: return "app"
            case .url: return "url"
            case .calendarEvent: return "calendarEvent"
            case .focusMode: return "focusMode"
            case .idleSpan: return "idleSpan"
            case .screenshotText: return "screenshotText"
            case .ruleFired: return "ruleFired"
            case .custom(let kind, _): return kind
            }
        }
    }
}
