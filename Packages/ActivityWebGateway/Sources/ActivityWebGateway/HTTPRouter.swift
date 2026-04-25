import Foundation
import ActivityCore
import ActivityIPC

/// Maps an incoming HTTP request to a JSON response by delegating to an
/// `IPCHandler`. Keeps networking out of route logic so the router can be
/// unit-tested without binding a socket.
public struct HTTPRouter: Sendable {
    public struct Response: Sendable {
        public let status: Int
        public let body: Data
        public let contentType: String

        public init(status: Int, body: Data, contentType: String = "application/json") {
            self.status = status
            self.body = body
            self.contentType = contentType
        }
    }

    public let handler: any IPCHandler

    public init(handler: any IPCHandler) {
        self.handler = handler
    }

    public func dispatch(method: String, path: String, query: [String: String]) async -> Response {
        guard method == "GET" else {
            return error(status: 405, message: "method not allowed")
        }
        do {
            switch path {
            case "/api/status":
                return try encode(await handler.status())

            case "/api/timeline":
                let req = TimelineRequest(
                    from: parseDate(query["from"]) ?? Date(timeIntervalSinceNow: -3600),
                    to: parseDate(query["to"]) ?? Date(),
                    bundleIDs: nil,
                    limit: parseInt(query["limit"])
                )
                return try encode(await handler.timeline(req))

            case "/api/events":
                let req = EventsRequest(
                    from: parseDate(query["from"]) ?? Date(timeIntervalSinceNow: -3600),
                    to: parseDate(query["to"]) ?? Date(),
                    source: nil,
                    limit: parseInt(query["limit"])
                )
                return try encode(await handler.events(req))

            case "/api/processes":
                let req = ProcessesQuery(
                    sortBy: parseSort(query["sort"]) ?? .memory,
                    order: parseOrder(query["order"]) ?? .desc,
                    limit: parseInt(query["limit"]) ?? 50
                )
                return try encode(await handler.listProcesses(req))

            case "/api/rules":
                return try encode(await handler.rules())

            default:
                return error(status: 404, message: "no route for \(path)")
            }
        } catch let ipc as IPCError {
            return error(status: 500, message: ipc.message)
        } catch {
            return self.error(status: 500, message: "\(error)")
        }
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) throws -> Response {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let body = try enc.encode(value)
        return Response(status: 200, body: body)
    }

    private func error(status: Int, message: String) -> Response {
        let body = (try? JSONEncoder().encode(["error": message])) ?? Data()
        return Response(status: status, body: body)
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        return f.date(from: s)
    }

    private func parseInt(_ s: String?) -> Int? {
        guard let s else { return nil }
        return Int(s)
    }

    private func parseSort(_ s: String?) -> ProcessesQuery.SortBy? {
        guard let s else { return nil }
        return ProcessesQuery.SortBy(rawValue: s)
    }

    private func parseOrder(_ s: String?) -> ProcessesQuery.Order? {
        guard let s else { return nil }
        return ProcessesQuery.Order(rawValue: s)
    }
}
