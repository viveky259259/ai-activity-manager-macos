import Foundation
import os
import ActivityCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// `CaptureSource` that polls an idle-seconds sampler on a dedicated Task and
/// feeds samples through an `IdleGate` to produce "begin"/"end" idle events.
///
/// The sampler and clock are injected so tests can script deterministic sequences.
public final class IdleSource: CaptureSource, @unchecked Sendable {
    public let identifier: String = "idle"

    private struct State {
        var continuation: AsyncStream<ActivityEvent>.Continuation?
        var task: Task<Void, Never>?
        var started: Bool = false
    }

    private let clock: any Clock
    private let gate: IdleGate
    private let pollInterval: TimeInterval
    private let sampler: @Sendable () -> TimeInterval
    private let state = OSAllocatedUnfairLock(initialState: State())

    public let events: AsyncStream<ActivityEvent>

    public init(
        clock: any Clock = SystemClock(),
        threshold: TimeInterval = 120,
        pollInterval: TimeInterval = 10,
        sampler: @escaping @Sendable () -> TimeInterval = IdleSource.defaultSampler
    ) {
        self.clock = clock
        self.gate = IdleGate(threshold: threshold)
        self.pollInterval = pollInterval
        self.sampler = sampler
        let (stream, continuation) = AsyncStream<ActivityEvent>.makeStream()
        self.events = stream
        state.withLock { $0.continuation = continuation }
    }

    public static let defaultSampler: @Sendable () -> TimeInterval = {
        #if canImport(CoreGraphics)
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .init(rawValue: ~0)!)
        #else
        return 0
        #endif
    }

    public func start() async throws {
        let already = state.withLock { s -> Bool in
            if s.started { return true }
            s.started = true
            return false
        }
        if already { return }

        let gateRef = self.gate
        let clockRef = self.clock
        let samplerRef = self.sampler
        let pollNanos = UInt64(max(0, pollInterval) * 1_000_000_000)
        let stateRef = self.state

        let task = Task { [pollNanos] in
            while !Task.isCancelled {
                let now = clockRef.now()
                let seconds = samplerRef()
                let sample = IdleSample(timestamp: now, secondsSinceLastEvent: seconds)
                let events = gateRef.ingest(sample: sample)
                let cont = stateRef.withLock { $0.continuation }
                for event in events {
                    cont?.yield(event)
                }
                do {
                    try await Task.sleep(nanoseconds: pollNanos)
                } catch {
                    return
                }
            }
        }
        state.withLock { $0.task = task }
    }

    public func stop() async {
        let (task, cont) = state.withLock { s -> (Task<Void, Never>?, AsyncStream<ActivityEvent>.Continuation?) in
            let t = s.task
            s.task = nil
            s.started = false
            let c = s.continuation
            s.continuation = nil
            return (t, c)
        }
        task?.cancel()
        cont?.finish()
    }
}
