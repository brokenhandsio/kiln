import Foundation
import Testing
@testable import Kiln

@Suite("DocC theme settings")
struct DocCThemeSettingsTests {
    private func sqlKitSettings() throws -> Data {
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        return try Data(contentsOf: fixtures.appendingPathComponent("docc-theme/sqlkit.json"))
    }

    @Test("SQLKit's colour alias resolves in both appearances; its technology icon is decoded")
    func sqlKit() throws {
        let theme = try JSONDecoder().decode(DocCThemeSettings.self, from: sqlKitSettings())
        #expect(theme.accentLight == "hsl(32, 80%, 60%)")
        #expect(theme.accentDark == "hsl(32, 77%, 63%)")
        #expect(theme.technologyIcon == "/sqlkit/images/SQLKit/vapor-sqlkit-logo.svg")
    }

    @Test("Colour aliases tolerate cycles and unsupported values without losing the icon")
    func aliases() throws {
        for value in ["var(--color-documentation-intro-accent)", "radial-gradient(red, blue)", "red; display: none"] {
            let data = try JSONSerialization.data(withJSONObject: ["theme": [
                "color": ["documentation-intro-accent": value], "icons": ["technology": "images/logo.svg"]
            ]])
            let theme = try JSONDecoder().decode(DocCThemeSettings.self, from: data)
            #expect(theme.accentLight == nil)
            #expect(theme.accentDark == nil)
            #expect(theme.technologyIcon == "images/logo.svg")
        }
        let theme = try JSONDecoder().decode(DocCThemeSettings.self, from: Data(##"{"theme":{"color":{"documentation-intro-accent":{"dark":"#abc"}}}}"##.utf8))
        #expect(theme.accentLight == "#abc")
        #expect(theme.accentDark == "#abc")
    }

    @Test("Archive trimming retains the theme settings and logo, but removes the DocC app")
    func trimming() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root.appendingPathComponent("images/SQLKit"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for path in ["theme-settings.json", "metadata.json", "index.html", "images/SQLKit/logo.svg"] {
            try Data("fixture".utf8).write(to: root.appendingPathComponent(path))
        }
        try DocCArchiveBuilder.stripToKilnEssentials(root)
        #expect(fm.fileExists(atPath: root.appendingPathComponent("theme-settings.json").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("images/SQLKit/logo.svg").path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("index.html").path))
    }

    @Test("Icons rebase to the mounted version and require an archive-local image")
    func iconPaths() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root.appendingPathComponent("images/SQLKit"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("svg".utf8).write(to: root.appendingPathComponent("images/SQLKit/logo with space.svg"))
        let urls = DocCURLs(moduleName: "SQLKit", version: PackageVersion("4-beta", ref: "main", modules: [Module("SQLKit")]), basePath: "/api")
        for icon in ["/sqlkit/images/SQLKit/logo%20with%20space.svg", "images/SQLKit/logo%20with%20space.svg"] {
            let data = try JSONSerialization.data(withJSONObject: ["theme": ["icons": ["technology": icon]]])
            let theme = try JSONDecoder().decode(DocCThemeSettings.self, from: data)
            #expect(theme.iconURL(archiveURL: root, urls: urls) == "/api/sqlkit/4-beta/images/SQLKit/logo%20with%20space.svg")
        }
        for icon in ["/sqlkit/images/missing.svg", "https://example.com/images/logo.svg", "//example.com/images/logo.svg", "images/../logo.svg", "images/%2e%2e/logo.svg"] {
            let data = try JSONSerialization.data(withJSONObject: ["theme": ["icons": ["technology": icon]]])
            let theme = try JSONDecoder().decode(DocCThemeSettings.self, from: data)
            #expect(theme.iconURL(archiveURL: root, urls: urls) == nil)
        }
    }

    @Test("Landing pages inherit icons, honour explicit overrides, and keep host colours")
    func rendering() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("kiln-theme-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let content = root.appendingPathComponent("Content")
        let output = root.appendingPathComponent("site")
        for version in ["3", "4-beta"] {
            let parent = content.appendingPathComponent("archives/\(version)")
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            let archive = parent.appendingPathComponent("Queues.doccarchive")
            try fm.copyItem(at: fixtures.appendingPathComponent("docc/Queues.doccarchive"), to: archive)
            try sqlKitSettings().write(to: archive.appendingPathComponent("theme-settings.json"))
            try fm.createDirectory(at: archive.appendingPathComponent("images/SQLKit"), withIntermediateDirectories: true)
            try Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"/>"#.utf8)
                .write(to: archive.appendingPathComponent("images/SQLKit/vapor-sqlkit-logo.svg"))
        }
        func site(image: String? = nil) -> KilnSite {
            KilnSite(name: "API", url: "https://example.com", basePath: "/api", llmsText: false,
                     docc: DocCSite(packages: [APIPackage("vapor/queues", versions: [
                        PackageVersion("3", ref: "v3", isDefault: true, modules: [Module("Queues", image: image)]),
                        PackageVersion("4-beta", ref: "main", modules: [Module("Queues", image: image)])
                     ])]))
        }
        try await Kiln.build(site(), contentDirectory: content, outputDirectory: output, linkChecking: .off)
        func html(_ path: String) throws -> String { try String(contentsOf: output.appendingPathComponent(path), encoding: .utf8) }
        let landing = try html("queues/index.html")
        #expect(landing.contains("docc-header docc-module-header"))
        #expect(landing.contains("src=\"/api/queues/images/SQLKit/vapor-sqlkit-logo.svg\""))
        #expect(!landing.contains("docc-module-tinted"))
        #expect(!landing.contains("--docc-accent"))
        #expect(!landing.contains("hsl(32,"))
        #expect(try !html("queues/queue/index.html").contains("--docc-accent"))
        #expect(try !html("index.html").contains("docc-module-tinted"))
        #expect(try html("queues/4-beta/index.html").contains("src=\"/api/queues/4-beta/images/SQLKit/vapor-sqlkit-logo.svg\""))
        #expect(try !html("queues/queue/index.html").contains("docc-module-image"))
        #expect(fm.fileExists(atPath: output.appendingPathComponent("queues/4-beta/images/SQLKit/vapor-sqlkit-logo.svg").path))
        try await Kiln.build(site(), contentDirectory: content, outputDirectory: output, linkChecking: .off, incremental: true)
        #expect(try html("queues/index.html") == landing)
        let changedArchive = content.appendingPathComponent("archives/3/Queues.doccarchive")
        try fm.copyItem(at: changedArchive.appendingPathComponent("images/SQLKit/vapor-sqlkit-logo.svg"),
                        to: changedArchive.appendingPathComponent("images/SQLKit/new-logo.svg"))
        let changedSettings = String(decoding: try sqlKitSettings(), as: UTF8.self)
            .replacingOccurrences(of: "vapor-sqlkit-logo.svg", with: "new-logo.svg")
        try Data(changedSettings.utf8).write(to: changedArchive.appendingPathComponent("theme-settings.json"))
        try await Kiln.build(site(), contentDirectory: content, outputDirectory: output, linkChecking: .off, incremental: true)
        #expect(try html("queues/index.html").contains("src=\"/api/queues/images/SQLKit/new-logo.svg\""))
        try await Kiln.build(site(image: "assets/custom.svg"), contentDirectory: content, outputDirectory: output, linkChecking: .off)
        #expect(try html("queues/index.html").contains("src=\"/api/assets/custom.svg\""))

        let archive = content.appendingPathComponent("archives/3/Queues.doccarchive")
        try Data("not JSON".utf8).write(to: archive.appendingPathComponent("theme-settings.json"))
        let loaded = try DocCArchiveLoader().load(archiveURL: archive)
        #expect(loaded.themeSettings == nil)
        #expect(loaded.loadIssues.contains { $0.contains("theme-settings.json") })
        #expect(!loaded.pages.isEmpty)
        try await Kiln.build(site(), contentDirectory: content, outputDirectory: output, linkChecking: .off)
        #expect(try !html("queues/index.html").contains("docc-module-header"))
        #expect(try !html("queues/index.html").contains("docc-module-image"))
    }
}
