import Foundation
import ActivityCore
import ActivityIPC

/// Abstraction over the IPC surface the MCP tools rely on. Production wires
/// this to `IPCClient`; tests provide an in-process `FakeActivityClient`.
///
/// Keep this interface minimal: only methods a tool handler actually invokes
/// should live here, so new tools force an explicit interface update.
public protocol ActivityClientProtocol: Sendable {
    func status() async throws -> StatusResponse
    func timeline(_ request: TimelineRequest) async throws -> TimelineResponse
    func events(_ request: EventsRequest) async throws -> EventsResponse
    func rules() async throws -> RulesResponse
    func addRule(_ request: AddRuleRequest) async throws -> AddRuleResponse
    func toggleRule(_ request: ToggleRuleRequest) async throws
    func killApp(_ request: KillAppRequest) async throws -> KillAppResponse
    func setFocusMode(_ request: SetFocusRequest) async throws
    func listProcesses(_ request: ProcessesQuery) async throws -> ProcessesPage
}

/// Conform the existing `IPCClient` so production callers can plug it in as-is.
extension IPCClient: ActivityClientProtocol {}
