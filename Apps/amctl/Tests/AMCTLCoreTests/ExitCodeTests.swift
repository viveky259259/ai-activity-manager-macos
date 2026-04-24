import Testing
import Foundation
import ActivityIPC
@testable import AMCTLCore

@Suite("ExitCode mapping")
struct ExitCodeTests {

    @Test("hostUnreachable maps to exit code 4")
    func hostUnreachableMapping() {
        let code = ExitCodeMapper.code(for: IPCError.hostUnreachable)
        #expect(code == .hostUnreachable)
        #expect(code.rawValue == 4)
    }

    @Test("permission-denied ipc error maps to 3")
    func permissionMapping() {
        let err = IPCError(code: "permission_denied", message: "tcc")
        let code = ExitCodeMapper.code(for: err)
        #expect(code == .permission)
        #expect(code.rawValue == 3)
    }

    @Test("action refused ipc error maps to 5")
    func actionRefusedMapping() {
        let err = IPCError(code: "action_refused", message: "cooldown")
        #expect(ExitCodeMapper.code(for: err) == .actionRefused)
    }

    @Test("generic error falls through to hostUnreachable")
    func unknownErrorFallthrough() {
        struct Dummy: Error {}
        #expect(ExitCodeMapper.code(for: Dummy()) == .hostUnreachable)
    }
}
