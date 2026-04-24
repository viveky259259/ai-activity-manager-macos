import Foundation
import GRDB
import ActivityCore

struct RuleRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "rules"

    var id: String
    var name: String
    var nl_source: String
    var mode: String
    var confirm_policy: String
    var cooldown_seconds: Double
    var trigger_json: String
    var condition_json: String?
    var actions_json: String
    var created_at: Double
    var updated_at: Double

    static func from(_ rule: Rule) throws -> RuleRecord {
        let encoder = JSONEncoder()
        let triggerData = try encoder.encode(rule.trigger)
        let actionsData = try encoder.encode(rule.actions)
        let conditionStr: String? = try {
            guard let c = rule.condition else { return nil }
            let d = try encoder.encode(c)
            return String(data: d, encoding: .utf8)
        }()
        return RuleRecord(
            id: rule.id.uuidString,
            name: rule.name,
            nl_source: rule.nlSource,
            mode: rule.mode.rawValue,
            confirm_policy: rule.confirm.rawValue,
            cooldown_seconds: rule.cooldown,
            trigger_json: String(data: triggerData, encoding: .utf8) ?? "",
            condition_json: conditionStr,
            actions_json: String(data: actionsData, encoding: .utf8) ?? "[]",
            created_at: rule.createdAt.timeIntervalSince1970,
            updated_at: rule.updatedAt.timeIntervalSince1970
        )
    }

    func toRule() throws -> Rule {
        guard let uuid = UUID(uuidString: id) else {
            throw StoreError.invalidRow("bad uuid: \(id)")
        }
        guard let mode = Rule.Mode(rawValue: mode) else {
            throw StoreError.invalidRow("bad mode: \(mode)")
        }
        guard let confirm = Rule.ConfirmPolicy(rawValue: confirm_policy) else {
            throw StoreError.invalidRow("bad confirm: \(confirm_policy)")
        }
        let decoder = JSONDecoder()
        let trigger = try decoder.decode(Trigger.self, from: Data(trigger_json.utf8))
        let actions = try decoder.decode([Action].self, from: Data(actions_json.utf8))
        let condition: Condition? = try {
            guard let c = condition_json else { return nil }
            return try decoder.decode(Condition.self, from: Data(c.utf8))
        }()
        return Rule(
            id: uuid,
            name: name,
            nlSource: nl_source,
            trigger: trigger,
            condition: condition,
            actions: actions,
            mode: mode,
            confirm: confirm,
            cooldown: cooldown_seconds,
            createdAt: Date(timeIntervalSince1970: created_at),
            updatedAt: Date(timeIntervalSince1970: updated_at)
        )
    }
}
