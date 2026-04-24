import Foundation
import ActivityCore
import ActivityIPC

/// Factory for the write (side-effecting) MCP tools. All write tools are
/// registered `enabled=false` per PRD §5; the host explicitly opts in per
/// tool via `ToolRegistry.setEnabled`.
public enum WriteTools {
    public static func make(client: any ActivityClientProtocol) -> [ToolDefinition] {
        [
            proposeRule(client: client),
            setRuleEnabled(client: client),
            killApp(client: client),
            setFocusMode(client: client),
        ]
    }

    // MARK: propose_rule

    private static func proposeRule(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "propose_rule",
            description: "Propose a new rule from a natural-language description. Always dry-run.",
            inputSchema: .object([
                "type": .string("object"),
                "required": .array([.string("nl_description")]),
                "properties": .object([
                    "nl_description": .object(["type": .string("string")]),
                ]),
            ]),
            enabled: false,
            isWrite: true,
            handler: { args in
                guard let nl = args["nl_description"]?.stringValue else {
                    throw JSONRPCError.invalidParams
                }
                let resp = try await client.addRule(AddRuleRequest(nl: nl))
                return try JSONBridge.encode(resp)
            }
        )
    }

    // MARK: set_rule_enabled

    private static func setRuleEnabled(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "set_rule_enabled",
            description: "Enable or disable an existing rule by id.",
            inputSchema: .object([
                "type": .string("object"),
                "required": .array([.string("rule_id"), .string("enabled")]),
                "properties": .object([
                    "rule_id": .object(["type": .string("string")]),
                    "enabled": .object(["type": .string("boolean")]),
                ]),
            ]),
            enabled: false,
            isWrite: true,
            handler: { args in
                guard let idString = args["rule_id"]?.stringValue,
                      let id = UUID(uuidString: idString),
                      let enabled = args["enabled"]?.boolValue else {
                    throw JSONRPCError.invalidParams
                }
                try await client.toggleRule(ToggleRuleRequest(id: id, enabled: enabled))
                return .object(["ok": .bool(true)])
            }
        )
    }

    // MARK: kill_app

    private static func killApp(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "kill_app",
            description: "Terminate a running app by bundle_id or by pid (exactly one). Uses the same safety rails as rule-driven kills.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object(["type": .string("string")]),
                    "pid": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                    ]),
                    "strategy": .object([
                        "type": .string("string"),
                        "enum": .array([.string("politeQuit"), .string("forceQuit"), .string("signal")]),
                    ]),
                    "force": .object(["type": .string("boolean")]),
                ]),
                "oneOf": .array([
                    .object(["required": .array([.string("bundle_id")])]),
                    .object(["required": .array([.string("pid")])]),
                ]),
            ]),
            enabled: false,
            isWrite: true,
            handler: { args in
                let bundle = args["bundle_id"]?.stringValue
                // Only treat pid as provided when it is actually an integer; reject strings.
                let pid: Int32?
                if let intValue = args["pid"]?.intValue {
                    guard intValue > 0, intValue <= Int(Int32.max) else {
                        throw JSONRPCError.invalidParams
                    }
                    pid = Int32(intValue)
                } else {
                    pid = nil
                }
                // Exactly one of bundle_id / pid must be set.
                guard (bundle != nil) != (pid != nil) else {
                    throw JSONRPCError.invalidParams
                }
                let strategyRaw = args["strategy"]?.stringValue ?? Action.KillStrategy.politeQuit.rawValue
                let strategy = Action.KillStrategy(rawValue: strategyRaw) ?? .politeQuit
                let force = args["force"]?.boolValue ?? false
                let req = KillAppRequest(
                    bundleID: bundle,
                    pid: pid,
                    strategy: strategy,
                    force: force,
                    confirmed: true
                )
                let resp = try await client.killApp(req)
                return try JSONBridge.encode(resp)
            }
        )
    }

    // MARK: set_focus_mode

    private static func setFocusMode(client: any ActivityClientProtocol) -> ToolDefinition {
        ToolDefinition(
            name: "set_focus_mode",
            description: "Set macOS focus mode; pass null to clear.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "mode_name": .object(["type": .array([.string("string"), .string("null")])]),
                ]),
            ]),
            enabled: false,
            isWrite: true,
            handler: { args in
                let mode = args["mode_name"]?.stringValue
                try await client.setFocusMode(SetFocusRequest(mode: mode))
                return .object(["ok": .bool(true)])
            }
        )
    }
}
