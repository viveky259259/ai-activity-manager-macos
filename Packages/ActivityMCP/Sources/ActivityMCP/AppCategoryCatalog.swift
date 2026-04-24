import Foundation

/// Static bundle-ID → category mapping, loaded once from
/// `Resources/app-categories.json`. Designed for O(1) lookup on every
/// process listing request without re-parsing.
public struct AppCategoryCatalog: Sendable {
    public let version: Int
    public let categories: [String]
    public let entries: [String: String]

    public func category(for bundleID: String?) -> String? {
        guard let id = bundleID, !id.isEmpty else { return nil }
        return entries[id]
    }

    public static let shared: AppCategoryCatalog = {
        guard let url = Bundle.module.url(forResource: "app-categories", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(RawCatalog.self, from: data) else {
            // Failing closed is preferable to failing loud: a missing catalog
            // just means no category tags, not a runtime crash.
            return AppCategoryCatalog(version: 0, categories: [], entries: [:])
        }
        return AppCategoryCatalog(
            version: decoded.version,
            categories: decoded.categories,
            entries: decoded.map
        )
    }()

    private struct RawCatalog: Decodable {
        let version: Int
        let categories: [String]
        let map: [String: String]
    }
}
