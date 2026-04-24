import Foundation

// MARK: - JSONValue

/// A JSON value that can round-trip through `Codable`. Used for schema- and
/// transport-level message bodies where the shape is determined at runtime.
public indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let i = try? container.decode(Int.self) {
            self = .int(i)
            return
        }
        if let d = try? container.decode(Double.self) {
            self = .double(d)
            return
        }
        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }
        if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
            return
        }
        if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unable to decode JSONValue"
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

extension JSONValue {
    /// Value lookup helper for the `.object` case; returns nil for other shapes.
    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
}

// MARK: - JSONRPC request/response

/// JSON-RPC 2.0 identifier: string, integer, or null. Absent on notifications.
public enum JSONRPCID: Sendable, Equatable, Codable {
    case string(String)
    case int(Int)
    case null

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad id")
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .int(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }
}

public struct JSONRPCRequest: Sendable, Equatable, Codable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let method: String
    public let params: JSONValue?

    public init(jsonrpc: String = "2.0", id: JSONRPCID?, method: String, params: JSONValue? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCError: Sendable, Equatable, Codable, Error {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard error codes
    public static let parseError = JSONRPCError(code: -32700, message: "Parse error")
    public static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid request")
    public static func methodNotFound(_ method: String) -> JSONRPCError {
        .init(code: -32601, message: "Method not found: \(method)")
    }
    public static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params")
    public static let internalError = JSONRPCError(code: -32603, message: "Internal error")
}

public struct JSONRPCResponse: Sendable, Equatable, Codable {
    public let jsonrpc: String
    public let id: JSONRPCID
    public let result: JSONValue?
    public let error: JSONRPCError?

    public init(
        jsonrpc: String = "2.0",
        id: JSONRPCID,
        result: JSONValue? = nil,
        error: JSONRPCError? = nil
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }

    public init(id: JSONRPCID, result: JSONValue) {
        self.init(jsonrpc: "2.0", id: id, result: result, error: nil)
    }

    public init(id: JSONRPCID, error: JSONRPCError) {
        self.init(jsonrpc: "2.0", id: id, result: nil, error: error)
    }

    // Custom encoding so we never emit `"result":null` alongside `"error"` and
    // vice-versa; JSON-RPC 2.0 forbids both fields being present.
    private enum CodingKeys: String, CodingKey { case jsonrpc, id, result, error }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(jsonrpc, forKey: .jsonrpc)
        try c.encode(id, forKey: .id)
        if let error {
            try c.encode(error, forKey: .error)
        } else {
            try c.encode(result ?? .null, forKey: .result)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.jsonrpc = try c.decode(String.self, forKey: .jsonrpc)
        self.id = try c.decode(JSONRPCID.self, forKey: .id)
        self.result = try c.decodeIfPresent(JSONValue.self, forKey: .result)
        self.error = try c.decodeIfPresent(JSONRPCError.self, forKey: .error)
    }
}
