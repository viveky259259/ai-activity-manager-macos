import Foundation

public protocol CaptureSource: AnyObject, Sendable {
    var identifier: String { get }
    func start() async throws
    func stop() async
    var events: AsyncStream<ActivityEvent> { get }
}

public enum CaptureError: Error, Sendable, Equatable {
    case permissionDenied(String)
    case unavailable(String)
    case failed(String)
}
