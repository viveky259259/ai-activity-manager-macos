import Foundation
import os
import NIO
import NIOHTTP1
import NIOWebSocket
import NIOFoundationCompat
import ActivityIPC

/// HTTP/WebSocket gateway that exposes the IPC handler over `localhost:<port>`
/// so a Flutter web client can poll REST endpoints and stream live MCP audit
/// events. Lifecycle is managed by `AppDependencies`.
public final class WebGateway: @unchecked Sendable {
    public let port: Int
    public let host: String

    private let router: HTTPRouter
    private let broadcaster: BroadcastingAuditLogger
    private let staticFiles: StaticFileServer

    private let group: MultiThreadedEventLoopGroup
    private let channelBox = OSAllocatedUnfairLock<Channel?>(initialState: nil)

    public init(
        handler: any IPCHandler,
        broadcaster: BroadcastingAuditLogger,
        staticRoot: URL? = nil,
        host: String = "127.0.0.1",
        port: Int = 8765
    ) {
        self.router = HTTPRouter(handler: handler)
        self.broadcaster = broadcaster
        self.staticFiles = StaticFileServer(root: staticRoot)
        self.host = host
        self.port = port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    public func start() async throws {
        let router = self.router
        let broadcaster = self.broadcaster
        let staticFiles = self.staticFiles

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let upgrader = NIOWebSocketServerUpgrader(
                    shouldUpgrade: { (channel, head) -> EventLoopFuture<HTTPHeaders?> in
                        if head.uri == "/ws/events" {
                            return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
                        }
                        return channel.eventLoop.makeSucceededFuture(nil)
                    },
                    upgradePipelineHandler: { (channel, _) -> EventLoopFuture<Void> in
                        channel.pipeline.addHandler(
                            WebSocketBridgeHandler(broadcaster: broadcaster)
                        )
                    }
                )
                let httpHandler = HTTPRequestHandler(router: router, staticFiles: staticFiles)
                let config: NIOHTTPServerUpgradeConfiguration = (
                    upgraders: [upgrader],
                    completionHandler: { ctx in
                        ctx.pipeline.removeHandler(httpHandler, promise: nil)
                    }
                )
                return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: config).flatMap {
                    channel.pipeline.addHandler(httpHandler)
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)

        let ch = try await bootstrap.bind(host: host, port: port).get()
        channelBox.withLock { $0 = ch }
    }

    public func stop() async throws {
        if let ch = channelBox.withLock({ $0 }) {
            try? await ch.close()
        }
        try await group.shutdownGracefully()
    }
}

// MARK: - HTTP

final class HTTPRequestHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let router: HTTPRouter
    private let staticFiles: StaticFileServer
    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    init(router: HTTPRouter, staticFiles: StaticFileServer) {
        self.router = router
        self.staticFiles = staticFiles
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            bodyBuffer = nil
        case .body(var buf):
            if bodyBuffer == nil { bodyBuffer = context.channel.allocator.buffer(capacity: buf.readableBytes) }
            bodyBuffer?.writeBuffer(&buf)
        case .end:
            guard let head = requestHead else { return }
            self.requestHead = nil
            handle(context: context, head: head)
        }
    }

    private func handle(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let (path, query) = parsePathAndQuery(uri: head.uri)
        let method = "\(head.method)"

        // Try static files first when the path is not under /api or /ws.
        if !path.hasPrefix("/api") && !path.hasPrefix("/ws"), let asset = staticFiles.resolve(path: path) {
            send(context: context, status: .ok, body: asset.body, contentType: asset.contentType)
            return
        }

        let loop = context.eventLoop
        let routerCopy = router
        let writeContext = NIOLoopBound(context, eventLoop: loop)

        Task {
            let response = await routerCopy.dispatch(method: method, path: path, query: query)
            loop.execute {
                let ctx = writeContext.value
                let status = HTTPResponseStatus(statusCode: response.status)
                self.send(context: ctx, status: status, body: response.body, contentType: response.contentType)
            }
        }
    }

    private func send(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        body: Data,
        contentType: String
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: contentType)
        headers.add(name: "Content-Length", value: "\(body.count)")
        headers.add(name: "Access-Control-Allow-Origin", value: "*")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func parsePathAndQuery(uri: String) -> (String, [String: String]) {
        guard let q = uri.firstIndex(of: "?") else {
            return (uri, [:])
        }
        let path = String(uri[..<q])
        let queryString = String(uri[uri.index(after: q)...])
        var dict: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].removingPercentEncoding ?? parts[0]
                let val = parts[1].removingPercentEncoding ?? parts[1]
                dict[key] = val
            }
        }
        return (path, dict)
    }
}

// MARK: - WebSocket

final class WebSocketBridgeHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let broadcaster: BroadcastingAuditLogger
    private var pumpTask: Task<Void, Never>?
    private var subscriptionID: UUID?

    init(broadcaster: BroadcastingAuditLogger) {
        self.broadcaster = broadcaster
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let loop = context.eventLoop
        let bound = NIOLoopBound(context, eventLoop: loop)
        let broadcaster = self.broadcaster

        pumpTask = Task { [weak self] in
            let subscription = await broadcaster.subscribe()
            self?.subscriptionID = subscription.id
            for await record in subscription.events {
                guard !Task.isCancelled else { break }
                let payload = WebSocketBridgeHandler.encode(record)
                loop.execute {
                    let ctx = bound.value
                    var buf = ctx.channel.allocator.buffer(capacity: payload.count)
                    buf.writeBytes(payload)
                    let frame = WebSocketFrame(fin: true, opcode: .text, data: buf)
                    ctx.writeAndFlush(NIOAny(frame), promise: nil)
                }
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        pumpTask?.cancel()
        if let id = subscriptionID {
            let broadcaster = self.broadcaster
            Task { await broadcaster.unsubscribe(id: id) }
        }
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .connectionClose:
            // Echo close and drop.
            let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.unmaskedData)
            let bound = NIOLoopBound(context, eventLoop: context.eventLoop)
            context.writeAndFlush(wrapOutboundOut(close)).whenComplete { _ in
                bound.value.close(promise: nil)
            }
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        default:
            break // ignore client text frames for now
        }
    }

    static func encode(_ record: AuditRecord) -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(record)) ?? Data()
    }
}
