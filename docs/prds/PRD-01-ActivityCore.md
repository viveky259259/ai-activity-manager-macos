# PRD-01 — ActivityCore

**Status:** proposed · **Owner:** core team · **Depends on:** none · **Blocks:** PRD-02 … PRD-09

## 1. Purpose

`ActivityCore` is the dependency-free domain + use-case layer. It owns:

- Domain types for activity events, sessions, rules, triggers, conditions, actions, queries.
- Port protocols to external systems (store, LLM, capture, actions, clock, redactor).
- Use case types that orchestrate ports.

It imports **only** Swift Foundation. It is the one module every other package depends on; it depends on none.

## 2. Non-goals

- No I/O (no files, no networks, no OS APIs beyond Foundation).
- No UI types.
- No concrete adapters — only protocols.

## 3. Domain types

### 3.1 `ActivityEvent`

```swift
public struct ActivityEvent: Hashable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let source: Source
    public let subject: Subject
    public let attributes: [String: String]

    public enum Source: String, Hashable, Sendable, CaseIterable {
        case frontmost, idle, calendar, focusMode, screenshot, rule, mcp, cli
    }

    public enum Subject: Hashable, Sendable {
        case app(bundleID: String, name: String)
        case url(host: String, path: String)
        case calendarEvent(id: String, title: String)
        case focusMode(name: String?)
        case idleSpan(startedAt: Date, endedAt: Date)
        case screenshotText(snippet: String)
        case ruleFired(ruleID: UUID, ruleName: String)
        case custom(kind: String, identifier: String)
    }
}
```

### 3.2 `ActivitySession`

A collapsed run of same-subject events.

```swift
public struct ActivitySession: Hashable, Sendable {
    public let id: UUID
    public let subject: ActivityEvent.Subject
    public let startedAt: Date
    public let endedAt: Date
    public let sampleCount: Int
    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}
```

### 3.3 Rule DSL

```swift
public struct Rule: Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var nlSource: String         // original English
    public var trigger: Trigger
    public var condition: Condition?
    public var actions: [Action]
    public var mode: Mode               // .dryRun, .active, .disabled
    public var confirm: ConfirmPolicy   // .never, .once, .always
    public var cooldown: TimeInterval   // min seconds between firings
    public var createdAt: Date
    public var updatedAt: Date

    public enum Mode: String, Hashable, Sendable { case dryRun, active, disabled }
    public enum ConfirmPolicy: String, Hashable, Sendable { case never, once, always }
}

public enum Trigger: Hashable, Sendable {
    case appFocused(bundleID: String, durationAtLeast: TimeInterval?)
    case appFocusLost(bundleID: String)
    case urlHostVisited(host: String, durationAtLeast: TimeInterval?)
    case idleEntered(after: TimeInterval)
    case idleEnded
    case calendarEventStarted(matching: String?)  // title regex
    case calendarEventEnded(matching: String?)
    case focusModeChanged(to: String?)
    case timeOfDay(hour: Int, minute: Int, weekdays: Set<Int>)
}

public indirect enum Condition: Hashable, Sendable {
    case and([Condition])
    case or([Condition])
    case not(Condition)
    case focusModeIs(String?)
    case betweenHours(start: Int, end: Int)
    case weekday(Set<Int>)
    case custom(key: String, op: CompareOp, value: String)

    public enum CompareOp: String, Hashable, Sendable {
        case eq, neq, gt, lt, gte, lte, contains, matches
    }
}

public enum Action: Hashable, Sendable {
    case setFocusMode(name: String?)          // nil = off
    case killApp(bundleID: String, strategy: KillStrategy, force: Bool)
    case launchApp(bundleID: String)
    case postNotification(title: String, body: String)
    case runShortcut(name: String)
    case logMessage(String)

    public enum KillStrategy: String, Hashable, Sendable {
        case politeQuit, forceQuit, signal
    }
}
```

### 3.4 Query types

```swift
public struct TimelineQuery: Hashable, Sendable {
    public var range: DateInterval
    public var sources: Set<ActivityEvent.Source>?
    public var bundleIDs: Set<String>?
    public var hostContains: String?
    public var fullText: String?
    public var limit: Int?
}

public struct QueryAnswer: Hashable, Sendable {
    public var answer: String
    public var citedSessions: [ActivitySession]
    public var provider: String
    public var tookMillis: Int
}
```

## 4. Ports (protocols)

### 4.1 `ActivityStore`

```swift
public protocol ActivityStore: Sendable {
    func append(_ events: [ActivityEvent]) async throws
    func events(in range: DateInterval, limit: Int?) async throws -> [ActivityEvent]
    func search(_ query: TimelineQuery) async throws -> [ActivityEvent]
    func sessions(in range: DateInterval, gapThreshold: TimeInterval) async throws -> [ActivitySession]
    func rules() async throws -> [Rule]
    func upsertRule(_ rule: Rule) async throws
    func deleteRule(id: UUID) async throws
}
```

### 4.2 `LLMProvider`

```swift
public protocol LLMProvider: Sendable {
    var identifier: String { get }
    var isLocal: Bool { get }
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}

public struct LLMRequest: Sendable {
    public var system: String
    public var user: String
    public var maxTokens: Int
    public var temperature: Double
    public var responseFormat: ResponseFormat
    public enum ResponseFormat: Sendable { case text, json(schema: String?) }
}

public struct LLMResponse: Sendable {
    public var text: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var model: String
}
```

### 4.3 `CaptureSource`

```swift
public protocol CaptureSource: AnyObject, Sendable {
    var identifier: String { get }
    func start() async throws
    func stop() async
    var events: AsyncStream<ActivityEvent> { get }
}
```

### 4.4 `ActionExecutor`

```swift
public protocol ActionExecutor: Sendable {
    func execute(_ action: Action) async throws -> ActionOutcome
}

public enum ActionOutcome: Hashable, Sendable {
    case succeeded
    case refused(reason: String)
    case notPermitted(reason: String)
    case escalated(previous: String)
    case dryRun(description: String)
}
```

### 4.5 `Clock`

```swift
public protocol Clock: Sendable {
    func now() -> Date
}
```

### 4.6 `Redactor`

```swift
public protocol Redactor: Sendable {
    func redact(_ text: String) -> String
    func redact(_ event: ActivityEvent) -> ActivityEvent
}
```

## 5. Use cases

Each is a `struct` with injected ports.

### 5.1 `RecordActivity`

Ingests events from all capture sources onto the event bus, writes to store in batches.

**Acceptance:**
- Given 1 event → 1 store.append call eventually.
- Given 50 events in <100ms → exactly 1 store.append call with all 50.
- If store.append throws, events are retried up to 3× then dropped with logged warning.

### 5.2 `QueryTimeline`

Runs a structured `TimelineQuery` against the store, returns events and sessions.

**Acceptance:**
- Results bounded by `limit`.
- Returns `[]` when range is empty — not throws.
- Deterministic ordering: `timestamp asc`, `id asc` as tiebreaker.

### 5.3 `AnswerTimelineQuestion`

NL question → retrieval via store → LLM answer citing sessions.

**Acceptance:**
- LLM receives a system prompt with cited-sessions-only rule.
- If no sessions match, returns "no data" answer without calling LLM.
- Truncates retrieved context to ≤ configured budget (default 4000 chars).
- Applies `Redactor` to all retrieved context before LLM call.

### 5.4 `CompileRuleFromNL`

NL description → structured `Rule`. LLM is the compiler; runtime is deterministic.

**Acceptance:**
- Returns a rule with `mode = .dryRun` unconditionally.
- Validates: trigger non-nil, at least one action, bundle IDs reverse-DNS shape.
- On invalid LLM output → throws `CompilerError.invalidShape`, no rule created.
- Round-trip stability: compile(nl) → serialize → parse → identical rule.

### 5.5 `EvaluateRules`

Given an event, find rules whose triggers fire, check conditions, dispatch actions.

**Acceptance:**
- Trigger matching is O(rules-for-this-trigger-kind), not O(all rules).
- Cooldown enforced per (rule, target) — rule cannot fire twice inside cooldown.
- Dry-run rules emit `dryRun` outcomes, never call real executor.
- Condition tree is short-circuited (and/or).

### 5.6 `SessionCollapser`

Pure function: `[ActivityEvent] × gapThreshold → [ActivitySession]`.

**Acceptance:**
- Same subject + gap ≤ threshold → merged.
- Different subject or gap > threshold → split.
- `sampleCount` equals number of source events per session.
- Deterministic regardless of input order (pre-sorts by timestamp).

## 6. Testing strategy

- **XCTest / Swift Testing** (`import Testing`).
- In-memory fakes for every port under `ActivityCore/TestSupport/`.
- `FakeClock`, `FakeStore`, `FakeLLMProvider`, `FakeExecutor`, `FakeCaptureSource`.
- Property-based tests for `SessionCollapser` (monotonic timestamps invariant).

## 7. Acceptance checklist

- [ ] All types are `Sendable` under Swift 6 strict concurrency.
- [ ] Zero `import` outside `Foundation`.
- [ ] Every public type has a doc comment.
- [ ] `swift test` passes with `-Xswiftc -warnings-as-errors`.
- [ ] Coverage ≥ 90% on use cases.
- [ ] No `fatalError` in non-test code.

## 8. Out of scope

- Persistence (PRD-02).
- Any OS-level adapter (PRD-03, 04, 05).
- Wire protocols (PRD-06).
