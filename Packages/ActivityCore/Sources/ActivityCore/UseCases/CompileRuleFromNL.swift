import Foundation

public struct CompileRuleFromNL: Sendable {
    public enum CompilerError: Error, Sendable, Equatable {
        case invalidShape(String)
        case providerFailed(String)
    }

    private let provider: LLMProvider
    private let clock: Clock

    public init(provider: LLMProvider, clock: Clock) {
        self.provider = provider
        self.clock = clock
    }

    public func compile(_ nl: String) async throws -> Rule {
        let trimmed = nl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CompilerError.invalidShape("empty input")
        }

        let request = LLMRequest(
            system: Self.systemPrompt,
            user: trimmed,
            maxTokens: 1024,
            temperature: 0,
            responseFormat: .json(schema: Self.ruleSchema)
        )

        let response: LLMResponse
        do {
            response = try await provider.complete(request)
        } catch {
            throw CompilerError.providerFailed(String(describing: error))
        }

        guard let data = response.text.data(using: .utf8) else {
            throw CompilerError.invalidShape("non-utf8 response")
        }

        let decoder = JSONDecoder()
        let dto: CompiledRuleDTO
        do {
            dto = try decoder.decode(CompiledRuleDTO.self, from: data)
        } catch {
            throw CompilerError.invalidShape("decode failed: \(error)")
        }

        let now = clock.now()
        let rule = try dto.toRule(
            nlSource: trimmed,
            createdAt: now,
            updatedAt: now
        )
        try Self.validate(rule)
        return rule
    }

    static func validate(_ rule: Rule) throws {
        guard !rule.actions.isEmpty else {
            throw CompilerError.invalidShape("rule must have at least one action")
        }
        for action in rule.actions {
            switch action {
            case .killApp(let bundleID, _, _),
                 .launchApp(let bundleID):
                guard bundleID.contains(".") else {
                    throw CompilerError.invalidShape("invalid bundle id: \(bundleID)")
                }
            default: break
            }
        }
        if rule.cooldown < 0 {
            throw CompilerError.invalidShape("cooldown must be non-negative")
        }
    }

    static let systemPrompt = """
    You compile English descriptions of activity automation rules into strict JSON.
    Output ONLY a single JSON object matching the provided schema. No prose, no markdown.
    New rules are always saved in dry-run mode; do not emit a 'mode' field.
    Bundle IDs must be reverse-DNS (e.g. com.apple.Safari).
    """

    static let ruleSchema = """
    {
      "type":"object",
      "required":["name","trigger","actions"],
      "properties":{
        "name":{"type":"string"},
        "trigger":{"type":"object"},
        "condition":{"type":"object"},
        "actions":{"type":"array","minItems":1},
        "cooldown":{"type":"number"}
      }
    }
    """
}

struct CompiledRuleDTO: Decodable, Sendable {
    var name: String
    var trigger: Trigger
    var condition: Condition?
    var actions: [Action]
    var cooldown: TimeInterval?
    var confirm: Rule.ConfirmPolicy?

    func toRule(nlSource: String, createdAt: Date, updatedAt: Date) throws -> Rule {
        Rule(
            name: name,
            nlSource: nlSource,
            trigger: trigger,
            condition: condition,
            actions: actions,
            mode: .dryRun,
            confirm: confirm ?? .never,
            cooldown: cooldown ?? 60,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
