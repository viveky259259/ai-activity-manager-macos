import Foundation

/// Helpers to move values between `Codable` models and `JSONValue`. Used by
/// tool handlers that want to wrap DTOs in JSON-RPC responses without writing
/// bespoke encoders.
enum JSONBridge {
    /// Encodes a Codable value to `JSONValue` via JSONSerialization to preserve
    /// numbers/bools/etc. Dates use ISO-8601.
    static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try convert(obj)
    }

    private static func convert(_ any: Any) throws -> JSONValue {
        if any is NSNull { return .null }
        if let n = any as? NSNumber {
            // Distinguish booleans from ints: NSNumber wraps both.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            let type = String(cString: n.objCType)
            if type == "f" || type == "d" {
                return .double(n.doubleValue)
            }
            return .int(n.intValue)
        }
        if let s = any as? String { return .string(s) }
        if let arr = any as? [Any] {
            return .array(try arr.map(convert))
        }
        if let dict = any as? [String: Any] {
            var out: [String: JSONValue] = [:]
            for (k, v) in dict { out[k] = try convert(v) }
            return .object(out)
        }
        throw EncodingError.invalidValue(any, .init(codingPath: [], debugDescription: "unsupported"))
    }

    /// Decodes a `JSONValue` into a Codable type.
    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    /// Parse an ISO-8601 date string from a JSON argument.
    static func parseDate(_ value: JSONValue?) -> Date? {
        guard let s = value?.stringValue else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        return iso2.date(from: s)
    }
}
