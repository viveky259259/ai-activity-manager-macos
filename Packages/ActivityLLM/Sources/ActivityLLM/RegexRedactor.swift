import Foundation
import ActivityCore

/// Regex-based implementation of ``Redactor`` that masks common PII patterns
/// (email, phone, credit card, IBAN, SSN, API keys, URLs with embedded
/// credentials) before activity data is sent to a cloud LLM.
///
/// Each match is replaced with the token `[REDACTED:KIND]` where `KIND` is an
/// upper-cased identifier for the pattern. Users may supply additional named
/// patterns through the initializer — they are applied after the built-ins.
///
/// `RegexRedactor` is value-typed in spirit but is a `final class` so that it
/// can pre-compile its `NSRegularExpression` objects once per instance. It is
/// fully `Sendable`: its internal state is immutable after initialization.
public final class RegexRedactor: Redactor, @unchecked Sendable {

    /// A named regex pattern applied during redaction.
    public struct Pattern: Sendable {
        /// The token used in place of matches, e.g. `EMAIL` yields
        /// `[REDACTED:EMAIL]`.
        public let kind: String
        /// The regular expression that drives this pattern.
        public let regex: NSRegularExpression
        /// Optional post-match validator. Returning `false` skips the match.
        public let validate: (@Sendable (String) -> Bool)?

        public init(
            kind: String,
            regex: NSRegularExpression,
            validate: (@Sendable (String) -> Bool)? = nil
        ) {
            self.kind = kind
            self.regex = regex
            self.validate = validate
        }
    }

    private let patterns: [Pattern]

    /// Creates a redactor seeded with the built-in patterns plus any
    /// caller-supplied extras. Extras are applied after the built-ins, in the
    /// order given.
    public init(extraPatterns: [Pattern] = []) {
        var all = Self.builtInPatterns()
        all.append(contentsOf: extraPatterns)
        self.patterns = all
    }

    // MARK: - Redactor

    public func redact(_ text: String) -> String {
        var current = text
        for pattern in patterns {
            current = Self.apply(pattern, to: current)
        }
        return current
    }

    public func redact(_ event: ActivityEvent) -> ActivityEvent {
        let redactedAttributes = event.attributes.mapValues { redact($0) }
        let newSubject: ActivityEvent.Subject
        switch event.subject {
        case .screenshotText(let snippet):
            newSubject = .screenshotText(snippet: redact(snippet))
        default:
            newSubject = event.subject
        }
        return ActivityEvent(
            id: event.id,
            timestamp: event.timestamp,
            source: event.source,
            subject: newSubject,
            attributes: redactedAttributes
        )
    }

    // MARK: - Pattern application

    private static func apply(_ pattern: Pattern, to input: String) -> String {
        let ns = input as NSString
        let matches = pattern.regex.matches(
            in: input,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        )
        if matches.isEmpty { return input }

        var result = ""
        var cursor = 0
        for match in matches {
            let matchRange = match.range
            let matched = ns.substring(with: matchRange)
            if let validate = pattern.validate, !validate(matched) {
                continue
            }
            if matchRange.location > cursor {
                result += ns.substring(
                    with: NSRange(location: cursor, length: matchRange.location - cursor)
                )
            }
            result += "[REDACTED:\(pattern.kind)]"
            cursor = matchRange.location + matchRange.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }

    // MARK: - Built-in patterns

    /// Builds the default list of patterns. Ordering matters: more specific
    /// tokens (URLs with credentials, API keys) are applied before broad ones
    /// (email, phone) so the narrow matches are not swallowed.
    public static func builtInPatterns() -> [Pattern] {
        var list: [Pattern] = []

        // URL with embedded credentials: scheme://user:pass@host/...
        if let rx = try? NSRegularExpression(
            pattern: #"\b[a-zA-Z][a-zA-Z0-9+\-.]*://[^\s:/@]+:[^\s:/@]+@[^\s]+"#,
            options: []
        ) {
            list.append(Pattern(kind: "URL_CREDENTIALS", regex: rx))
        }

        // API keys — recognizable vendor-specific prefixes.
        if let rx = try? NSRegularExpression(
            pattern: #"\b(?:sk-[A-Za-z0-9_\-]{16,}|pk_[A-Za-z0-9_\-]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})\b"#,
            options: []
        ) {
            list.append(Pattern(kind: "API_KEY", regex: rx))
        }

        // Email addresses.
        if let rx = try? NSRegularExpression(
            pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            options: []
        ) {
            list.append(Pattern(kind: "EMAIL", regex: rx))
        }

        // IBAN: 2-letter country code, 2 check digits, 11–30 alnum chars.
        if let rx = try? NSRegularExpression(
            pattern: #"\b[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}\b"#,
            options: []
        ) {
            list.append(Pattern(kind: "IBAN", regex: rx, validate: { candidate in
                // Very light sanity check: country code must be alpha, rest alnum.
                // Reject obvious API-key-like tokens (all digits or contains _ -).
                let trimmed = candidate.trimmingCharacters(in: .whitespaces)
                return trimmed.count >= 15 && trimmed.count <= 34
            }))
        }

        // US SSN: NNN-NN-NNNN with dashes or spaces required to avoid matching
        // arbitrary 9-digit numbers.
        if let rx = try? NSRegularExpression(
            pattern: #"\b\d{3}[-\s]\d{2}[-\s]\d{4}\b"#,
            options: []
        ) {
            list.append(Pattern(kind: "SSN", regex: rx))
        }

        // Credit-card numbers: 13–19 digits with optional spaces/dashes as
        // separators every 4 digits. Luhn-validated.
        if let rx = try? NSRegularExpression(
            pattern: #"\b(?:\d[ -]?){12,18}\d\b"#,
            options: []
        ) {
            list.append(Pattern(kind: "CREDIT_CARD", regex: rx, validate: { candidate in
                let digits = candidate.filter(\.isNumber)
                guard (13...19).contains(digits.count) else { return false }
                return luhn(digits)
            }))
        }

        // Phone numbers — E.164 and common US formats.
        if let rx = try? NSRegularExpression(
            pattern: #"(?:\+\d{1,3}[\s\-]?)?(?:\(\d{3}\)\s?|\d{3}[\s\-])\d{3}[\s\-]\d{4}|\+\d{10,15}"#,
            options: []
        ) {
            list.append(Pattern(kind: "PHONE", regex: rx))
        }

        return list
    }

    /// Luhn checksum validator. Public so callers building custom patterns can
    /// reuse it for their own card-style numbers.
    public static func luhn(_ digits: String) -> Bool {
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return false }
        var sum = 0
        let reversed = Array(digits.reversed())
        for (index, character) in reversed.enumerated() {
            guard let digit = character.wholeNumberValue else { return false }
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
}
