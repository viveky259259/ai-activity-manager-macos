import Foundation
import Testing
import ActivityCore
@testable import ActivityLLM

@Suite("RegexRedactor")
struct RedactorTests {

    // MARK: - Email

    @Test("email: positive samples are redacted", arguments: [
        "Contact me at alice@example.com today.",
        "Dual addresses: a.b+tag@sub.example.co.uk and bob_smith@example.org.",
        "trailing punctuation: jane.doe@foo.io.",
    ])
    func emailPositive(sample: String) {
        let r = RegexRedactor()
        let out = r.redact(sample)
        #expect(out.contains("[REDACTED:EMAIL]"))
        #expect(!out.contains("@"))
    }

    @Test("email: negative samples untouched", arguments: [
        "no email here",
        "price@ alone is not an address",
        "foo@bar is missing tld",
    ])
    func emailNegative(sample: String) {
        let r = RegexRedactor()
        #expect(r.redact(sample) == sample)
    }

    // MARK: - Phone

    @Test("phone: positive samples are redacted", arguments: [
        "Call +14155550123 today",
        "Call +1 415 555 0123 today",
        "US form (415) 555-0123",
        "US form 415-555-0123",
        "US form 415 555 0123",
    ])
    func phonePositive(sample: String) {
        let r = RegexRedactor()
        let out = r.redact(sample)
        #expect(out.contains("[REDACTED:PHONE]"))
    }

    @Test("phone: short numbers not flagged", arguments: [
        "year 2024",
        "room 302",
        "shortcode 911",
    ])
    func phoneNegative(sample: String) {
        let r = RegexRedactor()
        #expect(r.redact(sample) == sample)
    }

    // MARK: - Credit Card (Luhn-validated)

    @Test("credit card: Luhn-valid numbers redacted", arguments: [
        "card 4111 1111 1111 1111 end",
        "card 4111-1111-1111-1111 end",
        "card 5555555555554444 end",   // valid Mastercard test
        "amex 378282246310005 end",    // valid Amex test
    ])
    func creditCardPositive(sample: String) {
        let r = RegexRedactor()
        let out = r.redact(sample)
        #expect(out.contains("[REDACTED:CREDIT_CARD]"))
    }

    @Test("credit card: Luhn-invalid numbers untouched")
    func creditCardLuhnReject() {
        let r = RegexRedactor()
        // 16 digits, but Luhn fails:
        let sample = "card 1234 5678 9012 3456 end"
        let out = r.redact(sample)
        #expect(!out.contains("[REDACTED:CREDIT_CARD]"))
    }

    @Test("luhn: helper rejects obviously-bad inputs")
    func luhnHelper() {
        #expect(RegexRedactor.luhn("4111111111111111"))
        #expect(!RegexRedactor.luhn("4111111111111112"))
        #expect(!RegexRedactor.luhn(""))
        #expect(!RegexRedactor.luhn("abc"))
    }

    // MARK: - SSN

    @Test("ssn: positive samples redacted", arguments: [
        "ssn 123-45-6789 end",
        "ssn 123 45 6789 end",
    ])
    func ssnPositive(sample: String) {
        let r = RegexRedactor()
        let out = r.redact(sample)
        #expect(out.contains("[REDACTED:SSN]"))
    }

    @Test("ssn: unseparated digits not flagged as SSN")
    func ssnNegative() {
        // A 9-digit run with no separators could be many things; we must not
        // blindly redact. But it may still match credit-card pattern if Luhn
        // passes — we specifically pick a digit run whose Luhn check fails.
        let r = RegexRedactor()
        let out = r.redact("id 123456780 end")
        #expect(!out.contains("[REDACTED:SSN]"))
    }

    // MARK: - API keys

    @Test("api key: recognized prefixes redacted", arguments: [
        "token sk-abcdefghij0123456789 end",
        "token pk_abcdefghij0123456789 end",
        "token ghp_abcdefghij0123456789AB end",
        "arn AKIAABCDEFGHIJKLMNOP end",
    ])
    func apiKeyPositive(sample: String) {
        let r = RegexRedactor()
        let out = r.redact(sample)
        #expect(out.contains("[REDACTED:API_KEY]"))
    }

    @Test("api key: short tokens ignored")
    func apiKeyNegative() {
        let r = RegexRedactor()
        #expect(r.redact("token sk-short end") == "token sk-short end")
    }

    // MARK: - URL with credentials

    @Test("url credentials: redacted", arguments: [
        "visit https://alice:secret@example.com/path",
        "visit http://user:pass@localhost:8080/",
    ])
    func urlCredsPositive(sample: String) {
        let r = RegexRedactor()
        let out = r.redact(sample)
        #expect(out.contains("[REDACTED:URL_CREDENTIALS]"))
        #expect(!out.contains(":secret@"))
        #expect(!out.contains(":pass@"))
    }

    @Test("url credentials: plain URL untouched")
    func urlCredsNegative() {
        let r = RegexRedactor()
        let sample = "visit https://example.com/path"
        #expect(r.redact(sample) == sample)
    }

    // MARK: - IBAN

    @Test("iban: positive sample redacted")
    func ibanPositive() {
        let r = RegexRedactor()
        let out = r.redact("send to GB82WEST12345698765432 now")
        #expect(out.contains("[REDACTED:IBAN]"))
    }

    // MARK: - Extra patterns

    @Test("extra pattern: custom kind applied after built-ins")
    func extraPattern() throws {
        let rx = try NSRegularExpression(pattern: "secret-\\d+", options: [])
        let redactor = RegexRedactor(extraPatterns: [
            .init(kind: "CUSTOM", regex: rx)
        ])
        let out = redactor.redact("payload secret-42 end")
        #expect(out == "payload [REDACTED:CUSTOM] end")
    }

    // MARK: - Event redaction

    @Test("event: attribute values redacted, other fields untouched")
    func eventAttributes() {
        let r = RegexRedactor()
        let event = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            source: .frontmost,
            subject: .app(bundleID: "com.example.app", name: "App"),
            attributes: [
                "owner": "alice@example.com",
                "note": "no pii"
            ]
        )
        let redacted = r.redact(event)
        #expect(redacted.id == event.id)
        #expect(redacted.timestamp == event.timestamp)
        #expect(redacted.source == event.source)
        #expect(redacted.subject == event.subject)
        #expect(redacted.attributes["owner"] == "[REDACTED:EMAIL]")
        #expect(redacted.attributes["note"] == "no pii")
    }

    @Test("event: screenshotText snippet is redacted")
    func eventScreenshot() {
        let r = RegexRedactor()
        let event = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            source: .screenshot,
            subject: .screenshotText(snippet: "email me at bob@example.com please")
        )
        let redacted = r.redact(event)
        if case .screenshotText(let snippet) = redacted.subject {
            #expect(snippet.contains("[REDACTED:EMAIL]"))
            #expect(!snippet.contains("bob@"))
        } else {
            Issue.record("Expected screenshotText subject")
        }
    }

    @Test("event: non-screenshot subject passes through unchanged")
    func eventOtherSubject() {
        let r = RegexRedactor()
        let original = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            source: .frontmost,
            subject: .url(host: "alice:secret@example.com", path: "/")
        )
        // The URL subject's host should NOT be rewritten (subject is not a free
        // text field). Only screenshotText gets snippet rewriting.
        let redacted = r.redact(original)
        #expect(redacted.subject == original.subject)
    }
}
