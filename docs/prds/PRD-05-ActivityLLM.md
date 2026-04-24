# PRD-05 — ActivityLLM

**Status:** proposed · **Depends on:** PRD-01 · **Blocks:** PRD-09

## 1. Purpose

Implement the `LLMProvider` port with two concrete adapters plus a `Redactor`.

## 2. Adapters

### 2.1 `AnthropicProvider`

- Uses Anthropic Messages API.
- Transport: `URLSession` with streaming (`text/event-stream`) optional; MVP uses non-streaming.
- Auth: API key from Keychain (service `com.yourco.ActivityManager.anthropic`).
- Default model: `claude-opus-4-7` for rule compilation; `claude-sonnet-4-6` for recall; `claude-haiku-4-5-20251001` for classification.
- Prompt caching: enable on the compiler system prompt.

### 2.2 `FoundationModelsProvider`

- Uses Apple's on-device FoundationModels framework (macOS 15.1+, Apple Silicon).
- Fallback: if framework unavailable → throws `LLMError.unavailable`.

### 2.3 `FakeLLMProvider` (test support)

- Canned JSON / text responses keyed by input hash.
- Assertion helpers: `lastRequest`, `requestCount`.

## 3. Provider selection

`LLMProviderRegistry` picks a provider per feature:

```swift
public enum LLMFeature: String, Sendable {
    case ruleCompilation
    case recallAnswering
    case classification
    case summarization
}

public protocol LLMProviderRegistry: Sendable {
    func provider(for feature: LLMFeature) -> LLMProvider
}
```

User-configurable via settings; defaults:
- `ruleCompilation` → cloud
- `recallAnswering` → cloud (toggle to local)
- `classification` → local when available, else cloud
- `summarization` → cloud

## 4. `Redactor`

Rule-based regex redactor, applied before every cloud LLM call on any string derived from activity data.

Built-in patterns:
- Email addresses
- Phone numbers (E.164 + common US)
- Credit card numbers (Luhn-validated)
- IBAN, SSN, SIN patterns
- API keys (common prefixes: `sk-`, `pk_`, `ghp_`, `AKIA...`)
- URLs with credentials (`https://user:pass@...`)

Each match replaced with `[REDACTED:KIND]`.

Extensible via user-supplied pattern list in settings.

## 5. Prompts

Stored under `ActivityLLM/Resources/prompts/` as plain text:

- `rule_compiler_system.txt` — strict schema, JSON-only output, examples.
- `recall_system.txt` — must cite session IDs.
- `classifier_system.txt` — single-token category output.

System prompts are versioned; version is included in `LLMResponse.model` for traceability.

## 6. Testing strategy

- `FakeLLMProvider` covers all use-case tests in ActivityCore.
- `AnthropicProvider` unit tests: request serialization, response parsing, error branches (429, 500, malformed JSON).
- `AnthropicProvider` integration tests: guarded by `ANTHROPIC_API_KEY` env var, skipped otherwise.
- `Redactor`: property-based tests ensuring redacted output never contains patterns.

## 7. Acceptance

- [ ] `FakeLLMProvider` deterministic and hashable-keyed.
- [ ] `AnthropicProvider` retries once on 429 with backoff.
- [ ] `Redactor` all built-in patterns tested with positive + negative samples.
- [ ] Prompts loaded from bundle resources, not hard-coded strings.
- [ ] No API key ever logged or written to disk outside Keychain.

## 8. Out of scope

- Streaming responses (v1.1).
- Fine-tuned local model (future).
- Tool-use / function-calling (used by MCP pillar, not LLM core).
