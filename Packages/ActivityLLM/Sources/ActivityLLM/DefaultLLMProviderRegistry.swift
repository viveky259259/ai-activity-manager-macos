import Foundation
import os
import ActivityCore

/// In-memory, thread-safe implementation of ``LLMProviderRegistry``.
///
/// Callers supply a map from ``LLMFeature`` to concrete ``LLMProvider`` plus a
/// fallback provider used whenever the requested feature is not present in the
/// map. The registry is fully ``Sendable`` — internal state is guarded by an
/// ``OSAllocatedUnfairLock``.
public final class DefaultLLMProviderRegistry: LLMProviderRegistry, Sendable {

    private struct State {
        var providers: [LLMFeature: any LLMProvider]
        var fallback: any LLMProvider
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(providers: [LLMFeature: any LLMProvider] = [:], default fallback: any LLMProvider) {
        self.state = OSAllocatedUnfairLock(
            initialState: State(providers: providers, fallback: fallback)
        )
    }

    public func provider(for feature: LLMFeature) -> any LLMProvider {
        state.withLock { s in
            s.providers[feature] ?? s.fallback
        }
    }

    /// Associates `provider` with `feature`, replacing any existing mapping.
    public func register(_ provider: any LLMProvider, for feature: LLMFeature) {
        state.withLock { s in
            s.providers[feature] = provider
        }
    }

    /// Removes the mapping for `feature`, causing lookups to fall back to the
    /// default provider.
    public func unregister(_ feature: LLMFeature) {
        state.withLock { s in
            _ = s.providers.removeValue(forKey: feature)
        }
    }

    /// Replaces the fallback provider returned when no specific mapping exists.
    public func setDefault(_ provider: any LLMProvider) {
        state.withLock { s in
            s.fallback = provider
        }
    }
}
