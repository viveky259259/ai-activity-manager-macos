import Foundation
import os
import ActivityCore
@testable import ActivityCapture

/// Test double that conforms to `CaptureSource` and lets the test drive events
/// into its stream, simulate failure, and verify lifecycle calls.
final class FakeCaptureSource: CaptureSource, @unchecked Sendable {
    let identifier: String

    private struct State {
        var continuation: AsyncStream<ActivityEvent>.Continuation?
        var startCount: Int = 0
        var stopCount: Int = 0
        var startErrors: [any Error] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    let events: AsyncStream<ActivityEvent>

    init(identifier: String) {
        self.identifier = identifier
        let (stream, continuation) = AsyncStream<ActivityEvent>.makeStream()
        self.events = stream
        state.withLock { $0.continuation = continuation }
    }

    var startCount: Int { state.withLock { $0.startCount } }
    var stopCount: Int { state.withLock { $0.stopCount } }

    /// Queue up errors to be thrown on successive `start()` calls. After the
    /// queue is exhausted, `start()` succeeds.
    func queueStartErrors(_ errors: [any Error]) {
        state.withLock { $0.startErrors.append(contentsOf: errors) }
    }

    func yield(_ event: ActivityEvent) {
        let cont = state.withLock { $0.continuation }
        cont?.yield(event)
    }

    func finish() {
        let cont = state.withLock { $0.continuation }
        cont?.finish()
    }

    // MARK: CaptureSource

    func start() async throws {
        let err: (any Error)? = state.withLock { s in
            s.startCount += 1
            if s.startErrors.isEmpty { return nil }
            return s.startErrors.removeFirst()
        }
        if let err { throw err }
    }

    func stop() async {
        state.withLock { $0.stopCount += 1 }
    }
}
