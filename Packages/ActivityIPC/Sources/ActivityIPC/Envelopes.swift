import Foundation

/// IPC protocol constants.
public enum IPCProtocol {
    /// Current wire protocol version. Bump when making incompatible changes.
    public static let version: Int = 1

    /// Registered Mach service name for production use.
    public static let machServiceName: String = "com.yourco.ActivityManager.ipc"
}

/// Wrapper for every request crossing the XPC boundary.
public struct IPCRequest<T: Codable & Sendable>: Codable, Sendable {
    public let version: Int
    public let requestID: UUID
    public let payload: T

    public init(
        payload: T,
        requestID: UUID = UUID(),
        version: Int = IPCProtocol.version
    ) {
        self.version = version
        self.requestID = requestID
        self.payload = payload
    }
}

/// Wrapper for every response crossing the XPC boundary.
public struct IPCResponse<T: Codable & Sendable>: Codable, Sendable {
    public let requestID: UUID
    public let result: Result

    public init(requestID: UUID, result: Result) {
        self.requestID = requestID
        self.result = result
    }

    public enum Result: Codable, Sendable {
        case success(T)
        case error(IPCError)

        private enum CodingKeys: String, CodingKey {
            case kind
            case value
            case error
        }

        private enum Kind: String, Codable {
            case success
            case error
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)
            switch kind {
            case .success:
                let value = try container.decode(T.self, forKey: .value)
                self = .success(value)
            case .error:
                let err = try container.decode(IPCError.self, forKey: .error)
                self = .error(err)
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .success(let value):
                try container.encode(Kind.success, forKey: .kind)
                try container.encode(value, forKey: .value)
            case .error(let err):
                try container.encode(Kind.error, forKey: .kind)
                try container.encode(err, forKey: .error)
            }
        }
    }
}

/// Structured error returned through IPC. Conforms to `Error` so it can be thrown client-side.
public struct IPCError: Codable, Sendable, Error, Equatable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public static let versionMismatch = IPCError(
        code: "version_mismatch",
        message: "protocol version mismatch"
    )
    public static let hostUnreachable = IPCError(
        code: "host_unreachable",
        message: "activity manager is not running"
    )
    public static let invalidRequest = IPCError(
        code: "invalid_request",
        message: "malformed request"
    )
    public static let decodeFailure = IPCError(
        code: "decode_failure",
        message: "failed to decode IPC payload"
    )
    public static let encodeFailure = IPCError(
        code: "encode_failure",
        message: "failed to encode IPC payload"
    )
    public static let internalError = IPCError(
        code: "internal_error",
        message: "internal server error"
    )
}

/// Shared JSON coder configuration to ensure consistent date + UUID handling.
public enum IPCCoder {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
