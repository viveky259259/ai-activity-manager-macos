import Foundation
import Testing
@testable import ActivityMCP

@Suite("JSON-RPC codable")
struct JSONRPCTests {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private let decoder = JSONDecoder()

    @Test("decodes request with string id and params object")
    func decodeRequestStringID() throws {
        let json = #"""
        {"jsonrpc":"2.0","id":"abc","method":"tools/list","params":{"cursor":null}}
        """#
        let req = try decoder.decode(JSONRPCRequest.self, from: Data(json.utf8))

        #expect(req.jsonrpc == "2.0")
        #expect(req.method == "tools/list")
        #expect(req.id == .string("abc"))
        guard case .object(let params) = req.params else {
            Issue.record("expected params to be an object")
            return
        }
        #expect(params["cursor"] == .null)
    }

    @Test("decodes request with int id and no params (notification style without id)")
    func decodeRequestIntID() throws {
        let json = #"""
        {"jsonrpc":"2.0","id":42,"method":"ping"}
        """#
        let req = try decoder.decode(JSONRPCRequest.self, from: Data(json.utf8))
        #expect(req.id == .int(42))
        #expect(req.method == "ping")
        #expect(req.params == nil)
    }

    @Test("encodes success response")
    func encodeSuccessResponse() throws {
        let response = JSONRPCResponse(
            id: .int(7),
            result: .object(["ok": .bool(true)])
        )
        let data = try encoder.encode(response)
        let string = String(decoding: data, as: UTF8.self)
        #expect(string.contains("\"jsonrpc\":\"2.0\""))
        #expect(string.contains("\"id\":7"))
        #expect(string.contains("\"result\""))
        #expect(string.contains("\"ok\":true"))
        #expect(!string.contains("\"error\""))
    }

    @Test("encodes error response")
    func encodeErrorResponse() throws {
        let response = JSONRPCResponse(
            id: .string("x"),
            error: JSONRPCError(code: -32601, message: "method not found", data: nil)
        )
        let data = try encoder.encode(response)
        let string = String(decoding: data, as: UTF8.self)
        #expect(string.contains("\"id\":\"x\""))
        #expect(string.contains("\"code\":-32601"))
        #expect(string.contains("\"message\":\"method not found\""))
        #expect(!string.contains("\"result\""))
    }

    @Test("decodes notification (no id)")
    func decodeNotification() throws {
        let json = #"""
        {"jsonrpc":"2.0","method":"notifications/cancelled","params":{"reason":"user"}}
        """#
        let req = try decoder.decode(JSONRPCRequest.self, from: Data(json.utf8))
        #expect(req.id == nil)
        #expect(req.method == "notifications/cancelled")
    }

    @Test("JSONValue round-trips mixed structures")
    func jsonValueRoundTrip() throws {
        let value: JSONValue = .object([
            "n": .null,
            "b": .bool(false),
            "i": .int(3),
            "d": .double(1.5),
            "s": .string("hi"),
            "a": .array([.int(1), .string("two")]),
        ])
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(JSONValue.self, from: data)
        guard case .object(let obj) = decoded else {
            Issue.record("expected object")
            return
        }
        #expect(obj["n"] == .null)
        #expect(obj["b"] == .bool(false))
        #expect(obj["s"] == .string("hi"))
        // integer may come back as .int or .double depending on parser; allow either
        switch obj["i"] {
        case .int(3), .double(3.0): break
        default: Issue.record("expected 3, got \(String(describing: obj["i"]))")
        }
    }
}
