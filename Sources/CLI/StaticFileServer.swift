import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1

/// A minimal HTTP/1.1 static file server for local previewing of a built site.
///
/// Not intended for production — it serves files from a single directory with
/// pretty-URL resolution (`/foo/` → `foo/index.html`) and a custom `404.html`.
final class StaticFileServer {
    let directory: URL
    let host: String
    let port: Int
    /// Mount prefix to strip from request URIs (e.g. `/docs`), or `""`.
    let basePath: String
    private let group: MultiThreadedEventLoopGroup

    init(directory: URL, host: String, port: Int, basePath: String = "") {
        self.directory = directory
        self.host = host
        self.port = port
        self.basePath = basePath
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    }

    /// Bind and serve until the channel closes (i.e. until the process is interrupted).
    func run() throws {
        let directory = self.directory
        let basePath = self.basePath
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(StaticFileHandler(directory: directory, basePath: basePath))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        let channel = try bootstrap.bind(host: host, port: port).wait()
        try channel.closeFuture.wait()
    }

    func shutdown() {
        try? group.syncShutdownGracefully()
    }

    // MARK: - Pure helpers (testable)

    /// Map an HTTP request URI to a path relative to the served directory.
    ///
    /// - `/` and any path ending in `/` resolve to `…/index.html`.
    /// - An extensionless path (e.g. `/basics/routing`) is treated as a
    ///   directory and resolves to `…/index.html`.
    /// - A path with a file extension (e.g. `/llms.txt`) is used as-is.
    ///
    /// Returns `nil` if the path attempts to escape the root via `..`.
    ///
    /// When `basePath` is set (e.g. `/docs`), a matching leading prefix is
    /// stripped: in production the site is mounted under that subdirectory, but
    /// locally its contents are served from the root of `directory`, so visiting
    /// `/docs/foo/` resolves to `foo/index.html`.
    static func relativePath(forURI uri: String, basePath: String = "") -> String? {
        // Strip query and fragment.
        var path = uri
        if let separator = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            path = String(path[..<separator])
        }
        let endsWithSlash = path.hasSuffix("/")
        path = path.removingPercentEncoding ?? path

        var components: [String] = []
        for component in path.split(separator: "/") {
            switch component {
            case "..":
                if components.isEmpty { return nil }
                components.removeLast()
            case ".":
                continue
            default:
                components.append(String(component))
            }
        }

        // Drop a leading base-path prefix when present.
        let baseComponents = basePath.split(separator: "/").map(String.init)
        if !baseComponents.isEmpty, components.starts(with: baseComponents) {
            components.removeFirst(baseComponents.count)
        }

        guard let last = components.last else {
            return "index.html"
        }

        if endsWithSlash || !last.contains(".") {
            components.append("index.html")
        }
        return components.joined(separator: "/")
    }

    /// A `Content-Type` value for a file extension (lowercased, no dot).
    static func contentType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "md": return "text/markdown; charset=utf-8"
        case "txt": return "text/plain; charset=utf-8"
        case "xml": return "application/xml; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}

/// Per-connection handler that resolves a request to a file and writes the response.
///
/// Created inside a `@Sendable` channel initializer but only ever touched on its
/// own event loop, so the unchecked conformance is safe.
private final class StaticFileHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let directory: URL
    private let basePath: String
    private var requestHead: HTTPRequestHead?

    init(directory: URL, basePath: String = "") {
        self.directory = directory
        self.basePath = basePath
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
        case .body:
            break
        case .end:
            guard let head = requestHead else { return }
            requestHead = nil
            respond(to: head, context: context)
        }
    }

    private func respond(to head: HTTPRequestHead, context: ChannelHandlerContext) {
        // Honour HTTP keep-alive (the default for HTTP/1.1) so the browser can
        // reuse one connection for many assets instead of opening — and racing
        // to close — a fresh connection per request.
        let keepAlive = head.isKeepAlive

        guard let relative = StaticFileServer.relativePath(forURI: head.uri, basePath: basePath) else {
            writeResponse(context: context, status: .forbidden,
                          contentType: "text/plain; charset=utf-8",
                          body: Array("403 Forbidden".utf8), keepAlive: keepAlive)
            return
        }

        let fileURL = directory.appendingPathComponent(relative)
        if let data = try? Data(contentsOf: fileURL) {
            let ext = (relative as NSString).pathExtension
            writeResponse(context: context, status: .ok,
                          contentType: StaticFileServer.contentType(forExtension: ext),
                          body: Array(data), keepAlive: keepAlive)
            return
        }

        // Fall back to a custom 404 page if the site provides one.
        let notFoundURL = directory.appendingPathComponent("404.html")
        if let data = try? Data(contentsOf: notFoundURL) {
            writeResponse(context: context, status: .notFound,
                          contentType: "text/html; charset=utf-8", body: Array(data), keepAlive: keepAlive)
        } else {
            writeResponse(context: context, status: .notFound,
                          contentType: "text/plain; charset=utf-8",
                          body: Array("404 Not Found".utf8), keepAlive: keepAlive)
        }
    }

    private func writeResponse(context: ChannelHandlerContext, status: HTTPResponseStatus,
                               contentType: String, body: [UInt8], keepAlive: Bool) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: contentType)
        headers.add(name: "Content-Length", value: String(body.count))
        headers.add(name: "Connection", value: keepAlive ? "keep-alive" : "close")
        let responseHead = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

        guard !keepAlive else {
            // Reuse the connection for the next request — just flush this response.
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            return
        }

        // Close only once the whole response has actually been flushed to the
        // socket. Closing immediately can truncate a large response under parallel
        // load before its buffered bytes are written — which the browser surfaces
        // as "The network connection was lost".
        let promise = context.eventLoop.makePromise(of: Void.self)
        let boundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        promise.futureResult.whenComplete { _ in
            boundContext.value.close(promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: promise)
    }
}
