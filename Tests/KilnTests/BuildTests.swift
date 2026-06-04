import Testing
import Foundation
@testable import Kiln

@Suite("End-to-end build")
struct BuildTests {
    /// Build the bundled fixture docs into a fresh temporary directory.
    func buildFixture() async throws -> URL {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            Issue.record("Could not locate the Fixtures resource")
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        let contentDirectory = fixtures.appendingPathComponent("docs")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-test-\(UUID().uuidString)")

        let site = KilnSite(
            name: "Fixture Docs",
            url: "https://fixture.example.com",
            description: "Fixture site description.",
            image: "assets/card.png",
            twitterSite: "@fixture",
            languages: [
                .init(.english, isDefault: true),
                .init(.german, navTranslations: ["Section": "Abschnitt"],
                      localisation: .init(searchPlaceholder: "Suchen", tableOfContentsTitle: "Auf dieser Seite")),
            ]
        ) {
            Page("Home", "index.md")
            Section("Section") {
                Page("Page", "section/page.md")
            }
        }

        try await Kiln.build(site, contentDirectory: contentDirectory, outputDirectory: output)
        return output
    }

    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    @Test("Generates the expected file layout")
    func fileLayout() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let expectedFiles = [
            "index.html",
            "section/page/index.html",
            "de/index.html",
            "de/section/page/index.html",
            "search/search_index.json",
            "de/search/search_index.json",
            "404.html",
            "de/404.html",
            "_kiln/css/theme.css",
            "sitemap.xml",
        ]
        for file in expectedFiles {
            let url = output.appendingPathComponent(file)
            #expect(FileManager.default.fileExists(atPath: url.path), "Missing \(file)")
        }
    }

    @Test("Default and translated pages contain the right content")
    func localisedContent() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let home = try read(output.appendingPathComponent("index.html"))
        #expect(home.contains("Welcome to the test fixture site."))
        #expect(home.contains("admonition tip"))

        let germanHome = try read(output.appendingPathComponent("de/index.html"))
        #expect(germanHome.contains("Willkommen auf der Test-Seite."))
        // Section title is translated in the German navigation.
        #expect(germanHome.contains("Abschnitt"))
    }

    @Test("Missing translations fall back to the default language with a banner")
    func fallback() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let germanPage = try read(output.appendingPathComponent("de/section/page/index.html"))
        // The page has no German translation, so English content is shown…
        #expect(germanPage.contains("This page has no German translation"))
        // …and the reader is told it's a fallback.
        #expect(germanPage.contains("kiln-fallback"))
    }

    @Test("Pages include SEO and social-card meta tags")
    func seoMetaTags() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let home = try read(output.appendingPathComponent("index.html"))
        // Canonical + description (falls back to the site description).
        #expect(home.contains("<link rel=\"canonical\" href=\"https://fixture.example.com/\">"))
        #expect(home.contains("<meta name=\"description\" content=\"Fixture site description.\">"))
        // Open Graph.
        #expect(home.contains("<meta property=\"og:type\" content=\"website\">"))
        #expect(home.contains("<meta property=\"og:title\" content=\"Fixture Docs\">"))
        #expect(home.contains("<meta property=\"og:url\" content=\"https://fixture.example.com/\">"))
        #expect(home.contains("<meta property=\"og:image\" content=\"https://fixture.example.com/assets/card.png\">"))
        // Twitter card.
        #expect(home.contains("<meta name=\"twitter:card\" content=\"summary_large_image\">"))
        #expect(home.contains("<meta name=\"twitter:site\" content=\"@fixture\">"))

        // Per-page front matter overrides the description and image.
        let page = try read(output.appendingPathComponent("section/page/index.html"))
        #expect(page.contains("<meta name=\"description\" content=\"A page with its own social preview image.\">"))
        #expect(page.contains("<meta property=\"og:image\" content=\"https://fixture.example.com/assets/page-card.png\">"))
        #expect(page.contains("<meta property=\"og:type\" content=\"article\">"))
    }

    @Test("Intra-doc .md links are rewritten to pretty, locale-aware URLs")
    func linkRewriting() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let page = try read(output.appendingPathComponent("section/page/index.html"))
        #expect(page.contains("href=\"/\""))                       // ../index.md → /
        #expect(page.contains("href=\"/#section-one\""))           // ../index.md#section-one

        // The German build of the same (fallback) page points at German URLs.
        let germanPage = try read(output.appendingPathComponent("de/section/page/index.html"))
        #expect(germanPage.contains("href=\"/de/\""))
    }

    @Test("UI strings are localised per language, falling back to English")
    func localisedStrings() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        // German page uses the provided overrides…
        let germanHome = try read(output.appendingPathComponent("de/index.html"))
        #expect(germanHome.contains("placeholder=\"Suchen\""))
        #expect(germanHome.contains("Auf dieser Seite") || !germanHome.contains("kiln-toc-title"))
        // …and unset strings fall back to English.
        #expect(germanHome.contains("data-no-results=\"No results found\""))

        // English page uses the built-in defaults.
        let englishHome = try read(output.appendingPathComponent("index.html"))
        #expect(englishHome.contains("placeholder=\"Search\""))
    }

    @Test("robots.txt points at the sitemap")
    func robots() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }
        let robots = try read(output.appendingPathComponent("robots.txt"))
        #expect(robots.contains("Sitemap: https://fixture.example.com/sitemap.xml"))
    }

    @Test("Search index lists pages")
    func searchIndex() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let data = try Data(contentsOf: output.appendingPathComponent("search/search_index.json"))
        let index = try JSONDecoder().decode(SearchIndex.self, from: data)
        #expect(index.docs.count == 2)
        #expect(index.docs.contains { $0.title == "Home" })
    }
}
