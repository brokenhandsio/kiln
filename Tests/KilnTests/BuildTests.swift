import Testing
import Foundation
@testable import Kiln

@Suite("End-to-end build")
struct BuildTests {
    /// Build the bundled fixture docs into a fresh temporary directory.
    func buildFixture(linkChecking: LinkChecking = .warn) async throws -> URL {
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
            carbonAds: .init(serve: "TESTSERVE", placement: "fixture"),
            languages: [
                .init(.english, isDefault: true),
                .init(.german, navTranslations: ["Section": "Abschnitt"],
                      localisation: .init(searchPlaceholder: "Suchen", tableOfContentsTitle: "Auf dieser Seite")),
            ]
        ) {
            Page("Home", "index.md")
            Page("Landing", "landing.md")
            Section("Section") {
                Page("Page", "section/page.md")
            }
        }

        try await Kiln.build(site, contentDirectory: contentDirectory, outputDirectory: output, linkChecking: linkChecking)
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

    @Test("Per-page front matter can hide the sidebar and TOC rails")
    func chromeFlags() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        // A normal page shows both chrome rails (default-on ⇒ docs unchanged).
        let home = try read(output.appendingPathComponent("index.html"))
        #expect(home.contains("class=\"kiln-sidebar\""))
        #expect(home.contains("<aside class=\"kiln-toc\">"))
        #expect(!home.contains("kiln-no-sidebar"))
        #expect(!home.contains("kiln-no-toc"))

        // The landing page sets `sidebar: false` / `toc: false`: both asides are
        // gone and the layout reflows to full width.
        let landing = try read(output.appendingPathComponent("landing/index.html"))
        #expect(!landing.contains("class=\"kiln-sidebar\""))
        #expect(!landing.contains("<aside class=\"kiln-toc\">"))
        #expect(landing.contains("kiln-no-sidebar"))
        #expect(landing.contains("kiln-no-toc"))
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

    @Test("Carbon ads slot is emitted when configured")
    func carbonAds() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }
        let home = try read(output.appendingPathComponent("index.html"))
        #expect(home.contains("id=\"kiln-carbon\""))
        #expect(home.contains("data-serve=\"TESTSERVE\""))
        #expect(home.contains("data-placement=\"fixture\""))
    }

    @Test("Strict link checking passes — the fixture's internal links are all valid")
    func strictLinkCheckingPasses() async throws {
        let output = try await buildFixture(linkChecking: .error)
        try? FileManager.default.removeItem(at: output)
        // Reaching here without throwing means no broken internal links were found.
    }

    @Test("Generates AI/agent-friendly output (llms.txt, llms-full.txt, raw markdown)")
    func aiOutputs() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        // llms.txt index.
        let llms = try read(output.appendingPathComponent("llms.txt"))
        #expect(llms.hasPrefix("# Fixture Docs\n"))
        #expect(llms.contains("> Fixture site description."))
        #expect(llms.contains("- [Home](https://fixture.example.com/index.md)"))
        #expect(llms.contains("## Section"))
        #expect(llms.contains("https://fixture.example.com/section/page/index.md"))

        // Full corpus contains the page bodies.
        let full = try read(output.appendingPathComponent("llms-full.txt"))
        #expect(full.contains("Welcome to the test fixture site."))
        #expect(full.contains("This page has no German translation"))

        // Per-page raw markdown next to the HTML (default + localised).
        #expect(try read(output.appendingPathComponent("index.md")).contains("# Home"))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("section/page/index.md").path))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("de/index.md").path))

        // Each HTML page advertises its markdown alternate.
        let home = try read(output.appendingPathComponent("index.html"))
        #expect(home.contains("<link rel=\"alternate\" type=\"text/markdown\" href=\"/index.md\">"))

        // Best-effort translation discovery: the root index links other languages'
        // llms.txt under a "Translations" heading, and each language has its own.
        #expect(llms.contains("## Translations"))
        #expect(llms.contains("https://fixture.example.com/de/llms.txt"))
        let germanLLMS = try read(output.appendingPathComponent("de/llms.txt"))
        #expect(germanLLMS.contains("## Translations"))
        #expect(germanLLMS.contains("https://fixture.example.com/llms.txt"))  // links back to default
        #expect(germanLLMS.contains("/de/section/page/index.md"))             // localised page links
        // Only the default language gets the full corpus (avoids N× duplication).
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("de/llms-full.txt").path))
    }

    @Test("robots.txt points at the sitemap")
    func robots() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }
        let robots = try read(output.appendingPathComponent("robots.txt"))
        #expect(robots.contains("Sitemap: https://fixture.example.com/sitemap.xml"))
    }

    @Test("Unversioned sites emit no versioning artifacts (backward compatible)")
    func unversioned() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("versions.json").path))
        let home = try read(output.appendingPathComponent("index.html"))
        #expect(home.contains("window.kilnVersionBase = \"\""))
        #expect(!home.contains("kiln-version-switcher"))
        #expect(!home.contains("kiln-version-notice"))
        #expect(!home.contains("noindex"))
    }

    @Test("Search index lists pages")
    func searchIndex() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let data = try Data(contentsOf: output.appendingPathComponent("search/search_index.json"))
        let index = try JSONDecoder().decode(SearchIndex.self, from: data)
        // The fixture nav has three pages: Home, Landing, and Section › Page.
        #expect(index.docs.count == 3)
        #expect(index.docs.contains { $0.title == "Home" })
    }
}
