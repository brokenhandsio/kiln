import Testing
import Foundation
@testable import Kiln

@Suite("Documentation versioning")
struct VersioningTests {
    /// Build the versioned fixtures (a default `latest` with en+de and a
    /// latest-only guide, plus a non-default English-only `4.0` with different nav).
    func buildVersioned(linkChecking: LinkChecking = .warn) async throws -> URL {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            Issue.record("Could not locate the Fixtures resource")
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        let base = fixtures.appendingPathComponent("versioned")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-ver-\(UUID().uuidString)")

        let site = KilnSite(
            name: "Versioned Docs",
            url: "https://v.example.com",
            repository: .init(name: "GitHub", url: "https://github.com/x/y",
                              editURI: "https://github.com/x/y/edit/main/Content/latest/"),
            versions: [
                DocVersion(
                    id: "latest", name: "5.0 (latest)", isDefault: true,
                    contentDirectory: "latest",
                    languages: [.init(.english, isDefault: true), .init(.german)]
                ) {
                    Page("Home", "index.md")
                    Section("Section") { Page("Page", "section/page.md") }
                    Section("Guides") { Page("New", "guides/new.md") }
                },
                DocVersion(
                    id: "4.0", name: "4.0",
                    contentDirectory: "v4",
                    languages: [.init(.english, isDefault: true)]
                ) {
                    Page("Home", "index.md")
                    Section("Section") { Page("Page", "section/page.md") }
                    Section("Legacy") { Page("Old", "legacy/old.md") }
                },
                DocVersion(
                    id: "next", name: "2.0.0-alpha.1", isPrerelease: true,
                    contentDirectory: "next",
                    languages: [.init(.english, isDefault: true)]
                ) {
                    Page("Home", "index.md")
                },
            ]
        )

        try await Kiln.build(site, contentDirectory: base, outputDirectory: output, linkChecking: linkChecking)
        return output
    }

    func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    func exists(_ output: URL, _ path: String) -> Bool {
        FileManager.default.fileExists(atPath: output.appendingPathComponent(path).path)
    }

    @Test("Default version at root, others under /<id>/, with per-version structure")
    func layout() async throws {
        let output = try await buildVersioned()
        defer { try? FileManager.default.removeItem(at: output) }

        // Default (latest) at the root, en + de.
        for file in ["index.html", "de/index.html", "section/page/index.html",
                     "de/section/page/index.html", "guides/new/index.html"] {
            #expect(exists(output, file), "missing \(file)")
        }
        // v4 under /4.0/, English only, different nav.
        for file in ["4.0/index.html", "4.0/section/page/index.html", "4.0/legacy/old/index.html"] {
            #expect(exists(output, file), "missing \(file)")
        }
        // v4 has no German and no guides; latest has no legacy.
        #expect(!exists(output, "4.0/de/index.html"))
        #expect(!exists(output, "4.0/guides/new/index.html"))
        #expect(!exists(output, "legacy/old/index.html"))
    }

    @Test("Per-version search indexes and 404 pages")
    func perVersionSearchAnd404() async throws {
        let output = try await buildVersioned()
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(exists(output, "search/search_index.json"))
        #expect(exists(output, "de/search/search_index.json"))
        #expect(exists(output, "4.0/search/search_index.json"))
        #expect(!exists(output, "4.0/de/search/search_index.json"))
        #expect(exists(output, "404.html"))
        #expect(exists(output, "4.0/404.html"))
    }

    @Test("versions.json manifest lists every version")
    func manifest() async throws {
        let output = try await buildVersioned()
        defer { try? FileManager.default.removeItem(at: output) }

        let data = try Data(contentsOf: output.appendingPathComponent("versions.json"))
        let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let versions = try #require(array)
        #expect(versions.count == 3)

        let latest = try #require(versions.first { $0["id"] as? String == "latest" })
        #expect(latest["isDefault"] as? Bool == true)
        #expect(latest["path"] as? String == "/")
        #expect((latest["locales"] as? [String])?.sorted() == ["de", "en"])

        let v4 = try #require(versions.first { $0["id"] as? String == "4.0" })
        #expect(v4["isDefault"] as? Bool == false)
        #expect(v4["path"] as? String == "/4.0/")
        #expect(v4["locales"] as? [String] == ["en"])

        let next = try #require(versions.first { $0["id"] as? String == "next" })
        #expect(next["isPrerelease"] as? Bool == true)
        #expect(next["isDefault"] as? Bool == false)
    }

    @Test("Version switcher always links to each version's home page")
    func switcherGoesToVersionHome() async throws {
        let output = try await buildVersioned()
        defer { try? FileManager.default.removeItem(at: output) }

        // A switcher is rendered on the home page (two versions).
        let home = try read(output.appendingPathComponent("index.html"))
        #expect(home.contains("kiln-version-switcher"))
        #expect(home.contains("5.0 (latest)"))
        #expect(home.contains(">4.0<"))

        // From a deep latest page, the switcher option for 4.0 links to 4.0's home.
        let newGuide = try read(output.appendingPathComponent("guides/new/index.html"))
        #expect(newGuide.contains("href=\"/4.0/\" class=\"kiln-version-option"))

        // From a 4.0 page, the switcher option for latest is latest's home,
        // not the equivalent page (/section/page/).
        let v4Page = try read(output.appendingPathComponent("4.0/section/page/index.html"))
        #expect(v4Page.contains("href=\"/\" class=\"kiln-version-option"))
        #expect(!v4Page.contains("href=\"/section/page/\" class=\"kiln-version-option"))

        // German page → 4.0 (no German) lands on 4.0's default-locale home.
        let dePage = try read(output.appendingPathComponent("de/section/page/index.html"))
        #expect(dePage.contains("href=\"/4.0/\" class=\"kiln-version-option"))
    }

    @Test("Non-default versions are noindex + self-canonical")
    func seo() async throws {
        let output = try await buildVersioned()
        defer { try? FileManager.default.removeItem(at: output) }

        let v4Page = try read(output.appendingPathComponent("4.0/section/page/index.html"))
        #expect(v4Page.contains("<meta name=\"robots\" content=\"noindex\">"))
        #expect(v4Page.contains("<link rel=\"canonical\" href=\"https://v.example.com/4.0/section/page/\">"))

        // The default version is unaffected: no noindex, self canonical.
        let rootPage = try read(output.appendingPathComponent("section/page/index.html"))
        #expect(!rootPage.contains("noindex"))
        #expect(rootPage.contains("<link rel=\"canonical\" href=\"https://v.example.com/section/page/\">"))
    }

    @Test("Edit link is emitted only on the default (latest) version")
    func editLinkOnlyOnDefault() async throws {
        let output = try await buildVersioned()
        defer { try? FileManager.default.removeItem(at: output) }

        let rootPage = try read(output.appendingPathComponent("section/page/index.html"))
        #expect(rootPage.contains("kiln-edit-link"))
        #expect(rootPage.contains("https://github.com/x/y/edit/main/Content/latest/section/page.md"))

        let v4Page = try read(output.appendingPathComponent("4.0/section/page/index.html"))
        #expect(!v4Page.contains("kiln-edit-link"))
    }

    @Test("Old-version banner shows on non-default versions only")
    func banner() async throws {
        let output = try await buildVersioned()
        defer { try? FileManager.default.removeItem(at: output) }

        let v4Home = try read(output.appendingPathComponent("4.0/index.html"))
        #expect(v4Home.contains("kiln-version-notice"))
        #expect(v4Home.contains("href=\"/\"")) // link to latest home

        let rootHome = try read(output.appendingPathComponent("index.html"))
        #expect(!rootHome.contains("kiln-version-notice"))
    }

    @Test("Pre-release versions get a distinct banner and switcher styling")
    func preRelease() async throws {
        let output = try await buildVersioned()
        defer { try? FileManager.default.removeItem(at: output) }

        // The pre-release page shows the pre-release banner (note), not the older-version one (warning).
        let next = try read(output.appendingPathComponent("next/index.html"))
        #expect(next.contains("admonition note kiln-version-notice"))
        #expect(next.contains("pre-release version"))
        #expect(!next.contains("admonition warning kiln-version-notice"))
        #expect(next.contains("<meta name=\"robots\" content=\"noindex\">"))

        // The older (4.0) page keeps the warning banner.
        let v4 = try read(output.appendingPathComponent("4.0/index.html"))
        #expect(v4.contains("admonition warning kiln-version-notice"))

        // The switcher marks the pre-release entry.
        let home = try read(output.appendingPathComponent("index.html"))
        #expect(home.contains("kiln-version-option kiln-prerelease"))
    }

    @Test("Root sitemap covers the default version only")
    func sitemapIsolation() async throws {
        let output = try await buildVersioned()
        defer { try? FileManager.default.removeItem(at: output) }

        let sitemap = try read(output.appendingPathComponent("sitemap.xml"))
        #expect(sitemap.contains("https://v.example.com/section/page/"))
        #expect(!sitemap.contains("/4.0/"))
    }

    @Test("Search base path is set per version")
    func versionBasePath() async throws {
        let output = try await buildVersioned()
        defer { try? FileManager.default.removeItem(at: output) }

        let root = try read(output.appendingPathComponent("index.html"))
        #expect(root.contains("window.kilnVersionBase = \"\""))
        let v4 = try read(output.appendingPathComponent("4.0/index.html"))
        #expect(v4.contains("window.kilnVersionBase = \"/4.0\""))
        // Per-version search index URL.
        #expect(v4.contains("window.kilnSearchIndex = \"/4.0/search/search_index.json\""))
    }

    @Test("Per-version content + llms, and strict link checking passes")
    func contentAndLinks() async throws {
        let output = try await buildVersioned(linkChecking: .error)
        defer { try? FileManager.default.removeItem(at: output) }

        // Per-version llms under the version prefix; root llms is the default version.
        #expect(exists(output, "llms.txt"))
        #expect(exists(output, "4.0/llms.txt"))
        let v4llms = try read(output.appendingPathComponent("4.0/llms.txt"))
        #expect(v4llms.contains("https://v.example.com/4.0/legacy/old/index.md"))
        // Reaching here (linkChecking: .error) means no broken internal links per version.
    }
}
