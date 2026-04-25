import Foundation

/// Resolves a request path against an on-disk directory, returning the file
/// data and a content-type. Used to serve the Flutter `web/` build out of the
/// daemon. Returns `nil` if no static root is configured or the request
/// escapes the root via `..`.
public struct StaticFileServer: Sendable {
    public struct Asset: Sendable {
        public let body: Data
        public let contentType: String
    }

    public let root: URL?

    public init(root: URL?) {
        self.root = root
    }

    public func resolve(path: String) -> Asset? {
        guard let root else { return nil }
        // Default `/` to `index.html`.
        var rel = path == "/" ? "index.html" : String(path.dropFirst())
        if rel.contains("..") { return nil }
        if rel.isEmpty { rel = "index.html" }
        let file = root.appendingPathComponent(rel)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return Asset(body: data, contentType: contentType(for: file.pathExtension))
    }

    private func contentType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs":   return "application/javascript; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "json":        return "application/json; charset=utf-8"
        case "wasm":        return "application/wasm"
        case "svg":         return "image/svg+xml"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "ico":         return "image/x-icon"
        case "ttf":         return "font/ttf"
        case "woff":        return "font/woff"
        case "woff2":       return "font/woff2"
        default:            return "application/octet-stream"
        }
    }
}
