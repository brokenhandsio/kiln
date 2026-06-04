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
            languages: [
                .init(locale: "en", name: "English", isDefault: true),
                .init(locale: "de", name: "Deutsch", navTranslations: ["Section": "Abschnitt"]),
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
