import Foundation

public actor RecordActivity {
    private let store: ActivityStore
    private let maxRetries: Int
    private var pending: [ActivityEvent] = []
    private var flushTask: Task<Void, Never>?
    private let flushWindow: TimeInterval

    public init(store: ActivityStore, flushWindow: TimeInterval = 0.1, maxRetries: Int = 3) {
        self.store = store
        self.flushWindow = flushWindow
        self.maxRetries = maxRetries
    }

    public func ingest(_ event: ActivityEvent) async {
        pending.append(event)
        scheduleFlush()
    }

    public func ingest(_ events: [ActivityEvent]) async {
        pending.append(contentsOf: events)
        scheduleFlush()
    }

    public func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        await performFlush()
    }

    private func scheduleFlush() {
        if flushTask != nil { return }
        let window = flushWindow
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.performFlush()
        }
    }

    private func performFlush() async {
        flushTask = nil
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)

        var attempts = 0
        while attempts <= maxRetries {
            do {
                try await store.append(batch)
                return
            } catch {
                attempts += 1
                if attempts > maxRetries { return }
                let backoff = min(1.0, 0.05 * pow(2.0, Double(attempts)))
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
        }
    }
}
