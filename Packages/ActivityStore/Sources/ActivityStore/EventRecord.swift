import Foundation
import GRDB
import ActivityCore

struct EventRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "events"

    var id: String
    var timestamp: Double
    var source: String
    var subject_kind: String
    var subject_primary: String
    var subject_secondary: String
    var subject_json: String
    var attributes_json: String

    static func from(_ event: ActivityEvent) throws -> EventRecord {
        let encoder = JSONEncoder()
        let subjectData = try encoder.encode(event.subject)
        let attrsData = try encoder.encode(event.attributes)
        let (primary, secondary) = Self.primaryAndSecondary(for: event.subject)
        return EventRecord(
            id: event.id.uuidString,
            timestamp: event.timestamp.timeIntervalSince1970,
            source: event.source.rawValue,
            subject_kind: event.subject.kindName,
            subject_primary: primary,
            subject_secondary: secondary,
            subject_json: String(data: subjectData, encoding: .utf8) ?? "",
            attributes_json: String(data: attrsData, encoding: .utf8) ?? "{}"
        )
    }

    func toEvent() throws -> ActivityEvent {
        guard let uuid = UUID(uuidString: id) else {
            throw StoreError.invalidRow("bad uuid: \(id)")
        }
        guard let source = ActivityEvent.Source(rawValue: source) else {
            throw StoreError.invalidRow("bad source: \(source)")
        }
        let decoder = JSONDecoder()
        let subjectData = subject_json.data(using: .utf8) ?? Data()
        let subject = try decoder.decode(ActivityEvent.Subject.self, from: subjectData)
        let attrsData = attributes_json.data(using: .utf8) ?? Data()
        let attrs = (try? decoder.decode([String: String].self, from: attrsData)) ?? [:]
        return ActivityEvent(
            id: uuid,
            timestamp: Date(timeIntervalSince1970: timestamp),
            source: source,
            subject: subject,
            attributes: attrs
        )
    }

    private static func primaryAndSecondary(for subject: ActivityEvent.Subject) -> (String, String) {
        switch subject {
        case .app(let id, let name): return (id, name)
        case .url(let host, let path): return (host, path)
        case .calendarEvent(let id, let title): return (id, title)
        case .focusMode(let name): return (name ?? "off", "")
        case .idleSpan: return ("idle", "")
        case .screenshotText(let snippet): return ("ocr", snippet)
        case .ruleFired(let id, let name): return (id.uuidString, name)
        case .custom(let kind, let id): return (id, kind)
        }
    }
}

public enum StoreError: Error, Sendable, Equatable {
    case invalidRow(String)
    case notFound
}
