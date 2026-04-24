import Testing
@testable import ActivityMCP

@Suite("AppCategoryCatalog")
struct AppCategoryCatalogTests {
    @Test("loads from bundled resource")
    func loads() {
        let catalog = AppCategoryCatalog.shared
        #expect(catalog.version >= 1)
        #expect(!catalog.categories.isEmpty)
    }

    @Test("returns category for known bundle IDs")
    func knownBundles() {
        let catalog = AppCategoryCatalog.shared
        #expect(catalog.category(for: "com.apple.Safari") == "browser")
        #expect(catalog.category(for: "com.microsoft.VSCode") == "development")
        #expect(catalog.category(for: "com.spotify.client") == "entertainment")
        #expect(catalog.category(for: "com.tinyspeck.slackmacgap") == "communication")
    }

    @Test("returns nil for unmapped bundle IDs")
    func unknownBundle() {
        #expect(AppCategoryCatalog.shared.category(for: "com.made.up.app") == nil)
    }

    @Test("every mapped category appears in the declared categories list")
    func categoriesAreDeclared() {
        let catalog = AppCategoryCatalog.shared
        let declared = Set(catalog.categories)
        for (_, cat) in catalog.entries {
            #expect(declared.contains(cat), "undeclared category: \(cat)")
        }
    }

    @Test("nil bundle ID returns nil without crashing")
    func nilBundle() {
        #expect(AppCategoryCatalog.shared.category(for: nil) == nil)
    }
}
