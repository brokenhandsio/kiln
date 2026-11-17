import Testing
import Foundation
import LeafKit
@testable import Kiln

@Suite("Site and page context")
struct SiteContextTests {

    /// Every page renders the footer partial, so it prints the values under test.
    static let footer = """
        <footer>extra=[#(extra)] shared=[#(shared)] own=[#(own)] siteName=[#(site.name)]</footer>
        """

    @Test("extraContext values reach every page template")
    func extraContextOnPages() async throws {
        try await withSite(
            pages: ["index.md": "# Home", "guide.md": "# Guide"],
            configure: { $0.extraContext = ["extra": .string("everywhere")] }
        ) { output in
            let home = try read(output, "index.html")
            let guide = try read(output, "guide/index.html")
            #expect(home.contains("extra=[everywhere]"))
            #expect(guide.contains("extra=[everywhere]"))
        }
    }

    @Test("Kiln's own keys can't be shadowed by extraContext")
    func reservedKeysWin() async throws {
        try await withSite(
            pages: ["index.md": "# Home"],
            configure: { $0.extraContext = ["site": .string("shadowed")] }
        ) { output in
            let home = try read(output, "index.html")
            #expect(home.contains("siteName=[Context Test]"))
        }
    }

    @Test("pageContext gives each page its own values, over extraContext")
    func pageContextPerPage() async throws {
        try await withSite(
            pages: ["index.md": "# Home", "guide.md": "# Guide"],
            configure: { site in
                site.extraContext = ["shared": .string("site-wide")]
                site.pageContext = { path in
                    path == "guide.md"
                        ? ["own": .string("guide"), "shared": .string("guide-override")]
                        : ["own": .string("home")]
                }
            }
        ) { output in
            let home = try read(output, "index.html")
            #expect(home.contains("own=[home]"))
            #expect(home.contains("shared=[site-wide]"))
            let guide = try read(output, "guide/index.html")
            #expect(guide.contains("own=[guide]"))
            #expect(guide.contains("shared=[guide-override]"))
        }
    }

    @Test("Blog posts get pageContext by their path; listings get only extraContext")
    func blogContext() async throws {
        try await withSite(
            pages: [:],
            copyingFixture: "blog",
            blog: Blog(),
            configure: { site in
                site.extraContext = ["extra": .string("everywhere")]
                site.pageContext = { path in ["own": .string(path)] }
            }
        ) { output in
            let post = try read(output, "posts/first-post/index.html")
            #expect(post.contains("own=[posts/first-post.md]"))
            #expect(post.contains("extra=[everywhere]"))
            let index = try read(output, "index.html")
            #expect(index.contains("extra=[everywhere]"))
            #expect(index.contains("own=[]"))
        }
    }

    // MARK: - Helpers

    private func read(_ output: URL, _ path: String) throws -> String {
        try String(contentsOf: output.appendingPathComponent(path), encoding: .utf8)
    }

    /// Build a site from `pages` (path → markdown) with the footer above, let
    /// `configure` set its context, and hand the output directory to `check`.
    private func withSite(
        pages: [String: String],
        copyingFixture fixture: String? = nil,
        blog: Blog? = nil,
        configure: (inout KilnSite) -> Void,
        check: (URL) throws -> Void
    ) async throws {
        let fileManager = FileManager.default
        let shared = fileManager.temporaryDirectory.appendingPathComponent("kiln-theme-\(UUID().uuidString)")
        let content = fileManager.temporaryDirectory.appendingPathComponent("kiln-content-\(UUID().uuidString)", isDirectory: true)
        let output = fileManager.temporaryDirectory.appendingPathComponent("kiln-out-\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: shared)
            try? fileManager.removeItem(at: content)
            try? fileManager.removeItem(at: output)
        }

        let partials = shared.appendingPathComponent("templates/partials")
        try fileManager.createDirectory(at: partials, withIntermediateDirectories: true)
        try Self.footer.write(to: partials.appendingPathComponent("footer.leaf"), atomically: true, encoding: .utf8)
        if let fixture {
            let source = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
                .appendingPathComponent(fixture)
            try fileManager.copyItem(at: source, to: content)
        } else {
            try fileManager.createDirectory(at: content, withIntermediateDirectories: true)
        }
        for (path, markdown) in pages {
            let file = content.appendingPathComponent(path)
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try markdown.write(to: file, atomically: true, encoding: .utf8)
        }

        var site = KilnSite(
            name: "Context Test",
            url: "https://example.com",
            description: "Context test.",
            theme: .default(sharedLayers: [shared]),
            languages: [.init(.english, isDefault: true)],
            blog: blog
        ) {
            if blog == nil {
                for path in pages.keys.sorted() { Page(path, path) }
            }
        }
        configure(&site)
        try await Kiln.build(site, contentDirectory: content, outputDirectory: output, linkChecking: .off)
        try check(output)
    }
}
