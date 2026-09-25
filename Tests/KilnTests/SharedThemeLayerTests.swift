import Testing
import Foundation
@testable import Kiln

/// Exercises the shared theme layer feature: a site can stack additional theme
/// directories (typically shipped as SwiftPM resources by a shared design
/// package) between its own custom directory and Kiln's bundled default.
@Suite("Shared theme layers")
struct SharedThemeLayerTests {
    /// Create a throwaway theme directory containing a single overriding
    /// template at `templates/<relativePath>` with the given contents.
    private func makeThemeDirectory(footer: String? = nil) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-theme-\(UUID().uuidString)")
        let partials = root.appendingPathComponent("templates/partials")
        try FileManager.default.createDirectory(at: partials, withIntermediateDirectories: true)
        if let footer {
            try footer.write(to: partials.appendingPathComponent("footer.leaf"), atomically: true, encoding: .utf8)
        }
        return root
    }

    /// A minimal single-page content directory with one `index.md`.
    private func makeContentDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-content-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# Home\n\nHello.".write(to: root.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        return root
    }

    private func build(theme: Theme, content: URL) async throws -> String {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-out-\(UUID().uuidString)")
        let site = KilnSite(
            name: "Layer Test",
            url: "https://layer.example.com",
            description: "Shared layer test.",
            theme: theme,
            languages: [.init(.english, isDefault: true)]
        ) {
            Page("Home", "index.md")
        }
        try await Kiln.build(site, contentDirectory: content, outputDirectory: output, linkChecking: .off)
        defer { try? FileManager.default.removeItem(at: output) }
        return try String(contentsOf: output.appendingPathComponent("index.html"), encoding: .utf8)
    }

    @Test("A template resolves from a shared layer when absent locally")
    func sharedLayerProvidesTemplate() async throws {
        let custom = try makeThemeDirectory()  // no footer override
        let shared = try makeThemeDirectory(footer: "<footer>SHARED-LAYER-FOOTER</footer>")
        let content = try makeContentDirectory()
        defer {
            try? FileManager.default.removeItem(at: custom)
            try? FileManager.default.removeItem(at: shared)
            try? FileManager.default.removeItem(at: content)
        }

        let html = try await build(
            theme: .custom(directory: custom.path, sharedLayers: [shared]),
            content: content
        )
        #expect(html.contains("SHARED-LAYER-FOOTER"))
    }

    @Test("A site-local template overrides the shared layer")
    func customOverridesSharedLayer() async throws {
        let custom = try makeThemeDirectory(footer: "<footer>CUSTOM-FOOTER</footer>")
        let shared = try makeThemeDirectory(footer: "<footer>SHARED-LAYER-FOOTER</footer>")
        let content = try makeContentDirectory()
        defer {
            try? FileManager.default.removeItem(at: custom)
            try? FileManager.default.removeItem(at: shared)
            try? FileManager.default.removeItem(at: content)
        }

        let html = try await build(
            theme: .custom(directory: custom.path, sharedLayers: [shared]),
            content: content
        )
        #expect(html.contains("CUSTOM-FOOTER"))
        #expect(!html.contains("SHARED-LAYER-FOOTER"))
    }

    @Test("A shared layer can stack on the default theme")
    func sharedLayerOnDefaultTheme() async throws {
        let shared = try makeThemeDirectory(footer: "<footer>SHARED-LAYER-FOOTER</footer>")
        let content = try makeContentDirectory()
        defer {
            try? FileManager.default.removeItem(at: shared)
            try? FileManager.default.removeItem(at: content)
        }

        let html = try await build(theme: .default(sharedLayers: [shared]), content: content)
        #expect(html.contains("SHARED-LAYER-FOOTER"))
    }

    @Test("A missing shared layer directory throws a descriptive error")
    func missingSharedLayerThrows() async throws {
        let content = try makeContentDirectory()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-missing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: content) }

        await #expect(throws: ThemeError.self) {
            _ = try await build(theme: .default(sharedLayers: [missing]), content: content)
        }
    }
}
