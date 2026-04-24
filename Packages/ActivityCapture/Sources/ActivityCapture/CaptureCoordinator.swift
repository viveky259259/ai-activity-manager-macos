import Foundation
import os
import ActivityCore

/// Merges multiple `CaptureSource`s into a single `AsyncStream<ActivityEvent>`.
///
/// - Owns lifecycle (`start()` / `stop()`).
/// - On `start()` failure, restarts the failing source with exponential backoff
///   (doubling, capped at `backoffCapMillis`).
public final class CaptureCoordinator: @unchecked Sendable {
    private struct State {
        var continuation: AsyncStream<ActivityEvent>.Continuation?
        var statuses: [String: SourceStatus] = [:]
        var tasks: [Task<Void, Never>] = []
        var started: Bool = false
    }

    private let sources: [CaptureSource]
    private let backoffBaseMillis: UInt64
    private let backoffCapMillis: UInt64
    private let state = OSAllocatedUnfairLock(initialState: State())

    public let events: AsyncStream<ActivityEvent>

    public var statuses: [String: SourceStatus] {
        state.withLock { $0.statuses }
    }

    public init(
        sources: [CaptureSource],
        backoffBaseMillis: UInt64 = 500,
        backoffCapMillis: UInt64 = 60_000
    ) {
        self.sources = sources
        self.backoffBaseMillis = backoffBaseMillis
        self.backoffCapMillis = backoffCapMillis

        let (stream, continuation) = AsyncStream<ActivityEvent>.makeStream()
        self.events = stream
        state.withLock { s in
            s.continuation = continuation
            for src in sources { s.statuses[src.identifier] = .idle }
        }
    }

    public func start() async {
        let alreadyStarted: Bool = state.withLock { s in
            if s.started { return true }
            s.started = true
            return false
        }
        if alreadyStarted { return }

        for source in sources {
            let id = source.identifier
            let base = backoffBaseMillis
            let cap = backoffCapMillis

            let task = Task { [weak self] in
                guard let self else { return }
                var attempt: UInt64 = 0
                while !Task.isCancelled {
                    do {
                        try await source.start()
                        self.setStatus(id, .running)
                        await self.pumpEvents(from: source)
                        // If pumpEvents returns normally (stream finished), exit.
                        return
                    } catch {
                        self.setStatus(id, .failed("\(error)"))
                        let delay = min(cap, base << min(attempt, 20))
                        attempt &+= 1
                        do {
                            try await Task.sleep(nanoseconds: delay * 1_000_000)
                        } catch {
                            return
                        }
                    }
                }
            }
            state.withLock { $0.tasks.append(task) }
        }
    }

    public func stop() async {
        let (tasks, cont) = state.withLock { s -> ([Task<Void, Never>], AsyncStream<ActivityEvent>.Continuation?) in
            let t = s.tasks
            s.tasks = []
            s.started = false
            let c = s.continuation
            s.continuation = nil
            return (t, c)
        }
        for t in tasks { t.cancel() }
        for src in sources {
            await src.stop()
        }
        cont?.finish()
    }

    // MARK: Private

    private func pumpEvents(from source: CaptureSource) async {
        for await event in source.events {
            let cont = state.withLock { $0.continuation }
            cont?.yield(event)
        }
    }

    private func setStatus(_ id: String, _ status: SourceStatus) {
        state.withLock { $0.statuses[id] = status }
    }
}
