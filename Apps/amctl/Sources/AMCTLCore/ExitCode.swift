import Foundation
import ActivityIPC

/// Exit codes per PRD-07 section 5.
public enum AMCTLExitCode: Int32, Sendable {
    /// Success.
    case ok = 0
    /// Usage error (matches `ArgumentParser` default).
    case usage = 2
    /// Permission denied (TCC).
    case permission = 3
    /// Host unreachable (the app is not running).
    case hostUnreachable = 4
    /// Action refused (save dialog, cooldown, confirm timeout).
    case actionRefused = 5
    /// Not permitted (SIP, sandbox).
    case notPermitted = 6
}

public enum ExitCodeMapper {
    /// Map an error thrown by ``IPCClient`` (or surrounding code) to an exit code.
    public static func code(for error: any Error) -> AMCTLExitCode {
        if let ipc = error as? IPCError {
            return code(for: ipc)
        }
        return .hostUnreachable
    }

    public static func code(for ipcError: IPCError) -> AMCTLExitCode {
        switch ipcError.code {
        case IPCError.hostUnreachable.code:
            return .hostUnreachable
        case "permission_denied", "tcc_denied":
            return .permission
        case "action_refused", "cooldown", "confirm_timeout", "save_dialog":
            return .actionRefused
        case "not_permitted", "sip", "sandbox":
            return .notPermitted
        default:
            return .hostUnreachable
        }
    }
}
