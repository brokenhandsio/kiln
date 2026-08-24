import Testing
import Foundation
@testable import Kiln

@Suite("Unlisted pages")
struct UnlistedPagesTests {
    /// Build the `unlisted` fixture: two nav pages, plus `legal.md` (indexed,
    /// searchable, translated into German) and `secret.md` (opted out of both).
    func build(
        unlistedPages: [UnlistedPage] = [
            UnlistedPage("Legal", "legal.md"),
            UnlistedPage("Secret", "secret.md", searchable: false, indexed: false),
        ],
        linkChecking: LinkChecking = .error
    ) async throws -> URL {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            Issue.record("Could not locate the Fixtures resource")
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        let contentDirectory = fixtures.appendingPathComponent("unlisted")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-unlisted-\(UUID().uuidString)")

        let site = KilnSite(
            name: "Unlisted Docs",
            url: "https://unlisted.example.com",
            languages: [.init(.english, isDefault: true), .init(.german)],
            unlistedPages: unlistedPages
        ) {
            Page("Home", "index.md")
            Page("Guide", "guide.md")
        }

        try await Kiln.build(site, contentDirectory: contentDirectory, outputDirectory: output, linkChecking: linkChecking)
        return output
    }

    func read(_ output: URL, _ path: String) throws -> String {
        try String(contentsOf: output.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("An unlisted page is rendered with a pretty URL")
    func rendered() async throws {
        let output = try await build()
        defer { try? FileManager.default.removeItem(at: output) }

        let legal = try read(output, "legal/index.html")
        #expect(legal.contains("The legal notice."))
        #expect(legal.contains("<title>Legal · Unlisted Docs</title>"))
    }

    @Test("An unlisted page is absent from the navigation and the reading order")
    func absentFromNavigation() async throws {
        let output = try await build()
        defer { try? FileManager.default.removeItem(at: output) }

        // No nav entry on any page, including the unlisted page itself. Nav
        // entries render as `…>Title</a>`; the page's own <title>/<h1> and the
        // body link ("legal notice") don't match that shape.
        for page in ["index.html", "guide/index.html", "legal/index.html"] {
            let html = try read(output, page)
            #expect(!html.contains(">Legal</a>"), "\(page) shows the unlisted page in its nav")
        }

        // The unlisted page gets no previous/next, and it doesn't wedge itself
        // into the reading order between the two nav pages.
        let legal = try read(output, "legal/index.html")
        #expect(!legal.contains("kiln-prev"))
        #expect(!legal.contains("kiln-next"))

        let home = try read(output, "index.html")
        #expect(home.contains("kiln-next"))
        #expect(home.contains("Guide"))
    }

    @Test("Links to an unlisted page pass the link checker")
    func linkChecking() async throws {
        // The fixture's index.md links to legal.md; `.error` throws on a broken
        // link, so a clean build is the assertion.
        let output = try await build(linkChecking: .error)
        defer { try? FileManager.default.removeItem(at: output) }

        let home = try read(output, "index.html")
        #expect(home.contains("href=\"/legal/\""))
    }

    @Test("An unlisted page not registered in the config is not built")
    func unregisteredIsNotBuilt() async throws {
        let output = try await build(unlistedPages: [], linkChecking: .off)
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("legal/index.html").path))
    }

    @Test("Unlisted pages are translated like any other page")
    func translated() async throws {
        let output = try await build()
        defer { try? FileManager.default.removeItem(at: output) }

        let german = try read(output, "de/legal/index.html")
        #expect(german.contains("Der rechtliche Hinweis."))
        #expect(german.contains("hreflang=\"en\""))
    }

    @Test("searchable controls the search index")
    func searchIndex() async throws {
        let output = try await build()
        defer { try? FileManager.default.removeItem(at: output) }

        let index = try read(output, "search/search_index.json")
        #expect(index.contains("legal/"))
        #expect(!index.contains("secret/"))
    }

    @Test("indexed controls the sitemap, robots and llms-full.txt")
    func indexing() async throws {
        let output = try await build()
        defer { try? FileManager.default.removeItem(at: output) }

        let sitemap = try read(output, "sitemap.xml")
        #expect(sitemap.contains("https://unlisted.example.com/legal/"))
        #expect(!sitemap.contains("https://unlisted.example.com/secret/"))

        let legal = try read(output, "legal/index.html")
        #expect(!legal.contains("name=\"robots\" content=\"noindex\""))
        let secret = try read(output, "secret/index.html")
        #expect(secret.contains("name=\"robots\" content=\"noindex\""))

        let corpus = try read(output, "llms-full.txt")
        #expect(corpus.contains("The legal notice."))
        #expect(!corpus.contains("opted out of the search index"))
    }

    @Test("Unlisted pages stay out of the nav-shaped llms.txt index")
    func llmsIndex() async throws {
        let output = try await build()
        defer { try? FileManager.default.removeItem(at: output) }

        let index = try read(output, "llms.txt")
        #expect(index.contains("/guide/"))
        #expect(!index.contains("/legal/"))
    }

    @Test("A page in both the navigation and unlistedPages is rejected")
    func navigationConflict() {
        let site = KilnSite(
            name: "Docs", url: "https://x.com",
            unlistedPages: [UnlistedPage("Guide", "guide.md")]
        ) {
            Page("Home", "index.md")
            Section("Section") {
                Page("Guide", "guide.md")
            }
        }
        #expect(throws: ConfigurationError.self) { try site.validate() }
    }

    @Test("A duplicate unlisted page is rejected")
    func duplicate() {
        let site = KilnSite(
            name: "Docs", url: "https://x.com",
            unlistedPages: [UnlistedPage("Legal", "legal.md"), UnlistedPage("Legal Notice", "legal.md")]
        ) {
            Page("Home", "index.md")
        }
        #expect(throws: ConfigurationError.self) { try site.validate() }
    }

    @Test("Unlisted pages are declared per version")
    func versioned() throws {
        let site = KilnSite(
            name: "Docs", url: "https://x.com",
            versions: [
                DocVersion(id: "2.0", isDefault: true, contentDirectory: "docs/2.0",
                           unlistedPages: [UnlistedPage("Legal", "legal.md")]) {
                    Page("Home", "index.md")
                },
                DocVersion(id: "1.0", contentDirectory: "docs/1.0") {
                    Page("Home", "index.md")
                },
            ]
        )
        try site.validate()
        #expect(site.effectiveVersions.first(where: { $0.id == "2.0" })?.unlistedPages.count == 1)
        #expect(site.effectiveVersions.first(where: { $0.id == "1.0" })?.unlistedPages.isEmpty == true)
    }
}
