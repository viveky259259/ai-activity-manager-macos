import Foundation

public protocol Redactor: Sendable {
    func redact(_ text: String) -> String
    func redact(_ event: ActivityEvent) -> ActivityEvent
}

public struct PassthroughRedactor: Redactor {
    public init() {}
    public func redact(_ text: String) -> String { text }
    public func redact(_ event: ActivityEvent) -> ActivityEvent { event }
}
