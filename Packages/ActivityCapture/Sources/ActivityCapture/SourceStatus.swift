import Foundation

public enum SourceStatus: Equatable, Sendable {
    case idle
    case running
    case failed(String)
}
