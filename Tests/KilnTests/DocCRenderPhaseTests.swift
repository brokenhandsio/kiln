import Testing
import Foundation
@testable import Kiln

/// Builds a real (if small) DocC site end-to-end from the Queues/XCTQueues
/// fixture archives and asserts the emitted static files: module landing pages,
/// symbol pages with themed HTML, and intra/cross-module links resolved to the
/// site's module-first URL scheme.
@Suite("DocC render phase")
struct DocCRenderPhaseTests {
    /// Stage a temp content directory whose `archives/default/` holds the two
    /// fixture archives, and build a DocC-only site into a temp output directory.
    private func buildSite() async throws -> URL {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            Issue.record("Could not locate the Fixtures resource")
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        let docc = fixtures.appendingPathComponent("docc")

        let fm = FileManager.default
        let content = fm.temporaryDirectory.appendingPathComponent("kiln-docc-content-\(UUID().uuidString)")
        let archives = content.appendingPathComponent("archives/default")
        try fm.createDirectory(at: archives, withIntermediateDirectories: true)
        for module in ["Queues", "XCTQueues"] {
            try fm.copyItem(at: docc.appendingPathComponent("\(module).doccarchive"),
                            to: archives.appendingPathComponent("\(module).doccarchive"))
        }
        // Add a referenced asset to the Queues archive to exercise asset copying
        // (the trimmed fixtures carry no images/ of their own).
        let images = archives.appendingPathComponent("Queues.doccarchive/images")
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: images.appendingPathComponent("diagram.png"))
        // A social/OG image asset in the content dir.
        let assets = content.appendingPathComponent("assets")
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: assets.appendingPathComponent("api-og.png"))

        let output = fm.temporaryDirectory.appendingPathComponent("kiln-docc-output-\(UUID().uuidString)")
        let site = KilnSite(
            name: "Vapor API",
            url: "https://api.vapor.codes",
            description: "API reference.",
            image: "assets/api-og.png",
            llmsText: true,
            docc: DocCSite(packages: [
                APIPackage("vapor/queues", group: "Core", versions: [.single(ref: "main", modules: [
                    Module("Queues"),
                    Module("XCTQueues", group: "Testing"),
                ])]),
            ])
        )
        try await Kiln.build(site, contentDirectory: content, outputDirectory: output, linkChecking: .off)
        return output
    }

    private func html(_ output: URL, _ relative: String) throws -> String {
        let url = output.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Issue.record("expected output file missing: \(relative)")
            throw ContentError.contentDirectoryNotFound(relative)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("Builds module landing pages for every module")
    func modulePages() async throws {
        let output = try await buildSite()
        let queues = try html(output, "queues/index.html")
        #expect(queues.contains("<h1>Queues</h1>"))
        // The themed shell is present (base template rendered, not just the body).
        #expect(queues.contains("<!DOCTYPE html>") || queues.lowercased().contains("<html"))
        // Discussion from the module landing.
        #expect(queues.contains("Sending emails outside of the main request thread"))

        let xct = try html(output, "xctqueues/index.html")
        #expect(xct.contains("<h1>XCTQueues</h1>"))
    }

    @Test("Builds a catalog landing page at the site root")
    func catalog() async throws {
        let output = try await buildSite()
        let index = try html(output, "index.html")
        // The site title + a grouped card linking to each module's landing.
        #expect(index.contains("<h1>Vapor API</h1>"))
        #expect(index.contains("docc-catalog-card"))
        #expect(index.contains("href=\"/queues/\""))
        #expect(index.contains("href=\"/xctqueues/\""))
        #expect(index.contains(">Queues</span>") || index.contains("Queues</span>"))
        // The landing keeps the sidebar with the module switcher (closed by
        // default) and no on-page TOC.
        #expect(index.contains("<details class=\"docc-select docc-select--module\">"))
        #expect(!index.contains("docc-expanded"))
        #expect(!index.contains("kiln-no-sidebar"))
        #expect(index.contains("kiln-no-toc"))
    }

    @Test("Builds a sitewide search index of default-version symbols")
    func searchIndex() async throws {
        let output = try await buildSite()
        // The sitewide index at the root; every page's search box points here.
        let indexData = try Data(contentsOf: output.appendingPathComponent("search/search_index.json"))
        let index = try JSONDecoder().decode(SearchIndex.self, from: indexData)
        let byLocation = Dictionary(index.docs.map { ($0.location, $0) }, uniquingKeysWith: { a, _ in a })

        // A symbol from each module, located root-relative (search.js prepends "/").
        let queue = try #require(byLocation["queues/queue/"])
        #expect(queue.title == "Queue")
        #expect(queue.text.contains("store and retrieve jobs"))   // abstract indexed
        #expect(byLocation["xctqueues/"] != nil)                  // sibling module → sitewide
        // The catalog/home is searchable.
        #expect(byLocation[""]?.title == "Vapor API")

        // Per-module fragments back the incremental assembly.
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("_kiln/search/queues.json").path))
    }

    @Test("The sitemap lists the catalog and every default-version DocC page")
    func sitemap() async throws {
        let output = try await buildSite()
        let sitemap = try html(output, "sitemap.xml")
        // The catalog (site root) and module landings/symbols are all listed,
        // absolute against the site URL.
        #expect(sitemap.contains("<loc>https://api.vapor.codes/</loc>"))
        #expect(sitemap.contains("<loc>https://api.vapor.codes/queues/</loc>"))
        #expect(sitemap.contains("<loc>https://api.vapor.codes/queues/queue/</loc>"))
        #expect(sitemap.contains("<loc>https://api.vapor.codes/xctqueues/</loc>"))
        // Symbol pages carry a <lastmod> (the module archive's build date, W3C).
        #expect(sitemap.contains("<loc>https://api.vapor.codes/queues/queue/</loc><lastmod>"))
        #expect(sitemap.range(of: "<lastmod>[0-9]{4}-[0-9]{2}-[0-9]{2}</lastmod>", options: .regularExpression) != nil)
    }

    @Test("Symbol page titles append the module; the landing keeps just its own")
    func pageTitleIncludesModule() async throws {
        let output = try await buildSite()
        // A symbol page reads "Queue · Queues · <site>" (the theme adds the site).
        let queue = try html(output, "queues/queue/index.html")
        #expect(queue.contains("<title>Queue · Queues · Vapor API</title>"))
        // The visible heading stays the bare symbol name, not the enriched title.
        #expect(queue.contains("<h1 class=\"docc-symbol-title\">Queue</h1>"))
        // The module landing is not doubled up ("Queues · Queues").
        let landing = try html(output, "queues/index.html")
        #expect(landing.contains("<title>Queues · Vapor API</title>"))
    }

    @Test("Symbol titles are tagged for the code font; module landings are not")
    func symbolTitleCodeFont() async throws {
        let output = try await buildSite()
        // A symbol page's <h1> carries the code-font class.
        let queue = try html(output, "queues/queue/index.html")
        #expect(queue.contains("<h1 class=\"docc-symbol-title\">Queue</h1>"))
        // The module landing's title is a framework name, not a symbol → plain <h1>.
        let landing = try html(output, "queues/index.html")
        #expect(landing.contains("<h1>Queues</h1>"))
        #expect(!landing.contains("docc-symbol-title"))
    }

    @Test("Symbol pages carry the OpenGraph social image")
    func ogImage() async throws {
        let output = try await buildSite()
        let queue = try html(output, "queues/queue/index.html")
        #expect(queue.contains("<meta property=\"og:image\" content=\"https://api.vapor.codes/assets/api-og.png\">"))
        // The image asset is copied to the output.
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("assets/api-og.png").path))
    }

    @Test("Writes an llms.txt module index and no full corpus")
    func llmsIndex() async throws {
        let output = try await buildSite()
        let llms = try String(contentsOf: output.appendingPathComponent("llms.txt"), encoding: .utf8)
        #expect(llms.contains("# Vapor API"))
        #expect(llms.contains("## Core"))
        #expect(llms.contains("[Queues](https://api.vapor.codes/queues/)"))
        #expect(llms.contains("## Testing"))
        // No full corpus for API reference.
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("llms-full.txt").path))
    }

    @Test("Only default versions are indexed for search")
    func searchExcludesNonDefault() async throws {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        let queuesArchive = fixtures.appendingPathComponent("docc/Queues.doccarchive")
        let fm = FileManager.default
        let content = fm.temporaryDirectory.appendingPathComponent("kiln-docc-2v-\(UUID().uuidString)")
        // Same fixture under two version ids: "4" (default) and "5-beta".
        for vid in ["4", "5-beta"] {
            let dir = content.appendingPathComponent("archives/\(vid)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(at: queuesArchive, to: dir.appendingPathComponent("Queues.doccarchive"))
        }
        let output = fm.temporaryDirectory.appendingPathComponent("kiln-docc-2v-out-\(UUID().uuidString)")
        let site = KilnSite(name: "API", url: "https://api.example.com", llmsText: false,
                            docc: DocCSite(packages: [APIPackage("vapor/queues", group: "Core", versions: [
                                PackageVersion("4", ref: "v4", isDefault: true, modules: [Module("Queues")]),
                                PackageVersion("5-beta", ref: "main", isPrerelease: true, modules: [Module("Queues")]),
                            ])]))
        try await Kiln.build(site, contentDirectory: content, outputDirectory: output, linkChecking: .off)

        let index = try JSONDecoder().decode(SearchIndex.self,
            from: Data(contentsOf: output.appendingPathComponent("search/search_index.json")))
        // Default (v4) symbols present at the module root; beta ones absent.
        #expect(index.docs.contains { $0.location == "queues/queue/" })
        #expect(!index.docs.contains { $0.location.hasPrefix("queues/5-beta/") })

        // The sitemap mirrors this: default-version pages listed, the noindex
        // beta version excluded.
        let sitemap = try html(output, "sitemap.xml")
        #expect(sitemap.contains("<loc>https://api.example.com/queues/queue/</loc>"))
        #expect(!sitemap.contains("/queues/5-beta/"))
    }

    @Test("Renders a symbol page with declaration, eyebrow, and TOC")
    func symbolPage() async throws {
        let output = try await buildSite()
        let queue = try html(output, "queues/queue/index.html")
        #expect(queue.contains("<h1 class=\"docc-symbol-title\">Queue</h1>"))
        #expect(queue.contains("docc-eyebrow"))          // role heading eyebrow
        #expect(queue.contains("<pre class=\"declaration\">"))
        // Curated Topics section for the protocol's members.
        #expect(queue.contains("Topics") || queue.contains("docc-topic"))
    }

    @Test("Symbol pages carry a breadcrumb trail (visible + BreadcrumbList JSON-LD)")
    func breadcrumbs() async throws {
        let output = try await buildSite()
        let method = try html(output, "queues/queue/dispatch(_:_:maxretrycount:delayuntil:id:)-630ll/index.html")

        // Visible trail: ancestors are links, the current page is an unlinked crumb.
        #expect(method.contains("<nav class=\"kiln-breadcrumb\""))
        #expect(method.contains("<a href=\"/queues/\">Queues</a>"))
        #expect(method.contains("<a href=\"/queues/queue/\">Queue</a>"))
        #expect(method.contains("aria-current=\"page\">dispatch"))

        // JSON-LD BreadcrumbList: Home → Queues → Queue → the method, in order.
        #expect(method.contains("\"@type\":\"BreadcrumbList\""))
        let list = try #require(method.range(of: "\"@type\":\"BreadcrumbList\""))
        let json = String(method[list.lowerBound...])
        let queuesPos = json.range(of: "\"name\":\"Queues\"")
        let queuePos = json.range(of: "\"name\":\"Queue\"")
        #expect(queuesPos != nil && queuePos != nil)
        #expect(queuesPos!.lowerBound < queuePos!.lowerBound, "module precedes the type in the trail")

        // The module landing has no ancestors → no breadcrumb.
        let landing = try html(output, "queues/index.html")
        #expect(!landing.contains("<nav class=\"kiln-breadcrumb\""))
    }

    @Test("A method page's type references resolve to site URLs")
    func linksResolve() async throws {
        let output = try await buildSite()
        let method = try html(output, "queues/queue/dispatch(_:_:maxretrycount:delayuntil:id:)-630ll/index.html")
        #expect(method.contains("<h1 class=\"docc-symbol-title\">dispatch(_:_:maxRetryCount:delayUntil:id:)</h1>"))
        // Declaration type `Job` links to its site page (module-first, stripped).
        #expect(method.contains("href=\"/queues/job/\""))
        // Parameters section rendered.
        #expect(method.contains("Parameters"))
    }

    @Test("Intra-module topic links point at the module-first scheme")
    func topicLinks() async throws {
        let output = try await buildSite()
        let landing = try html(output, "queues/index.html")
        // A curated member links to its stripped site URL.
        #expect(landing.contains("href=\"/queues/schedulebuilder/\""))
    }

    @Test("Archive assets are copied into the module dir; raw archives don't leak")
    func assetsAndNoLeak() async throws {
        let output = try await buildSite()
        let fm = FileManager.default
        // The archive's referenced asset lands under the module root
        // (matching the /images/… → /queues/images/… link rewrite).
        #expect(fm.fileExists(atPath: output.appendingPathComponent("queues/images/diagram.png").path))
        // The raw DocC archives directory is NOT copied into the output.
        #expect(!fm.fileExists(atPath: output.appendingPathComponent("archives").path))
    }

    @Test("Every page carries the module switcher with the current module flagged")
    func moduleSwitcher() async throws {
        let output = try await buildSite()
        let queue = try html(output, "queues/queue/index.html")
        #expect(queue.contains("docc-select--module"))
        // The current module is the toggle label and flagged in the list.
        #expect(queue.contains("<span class=\"docc-select-value\">Queues</span>"))
        #expect(queue.contains("<a class=\"docc-select-option is-current\" href=\"/queues/\">Queues</a>"))
        // The sibling module is listed to switch to.
        #expect(queue.contains("href=\"/xctqueues/\">XCTQueues</a>"))
        // Single-version package → no version switcher.
        #expect(!queue.contains("docc-select--version"))
    }

    @Test("Every page carries the module sidebar + the client-side highlight script")
    func sidebar() async throws {
        let output = try await buildSite()
        let queue = try html(output, "queues/queue/index.html")
        // The DocC sidebar is injected (not the empty nav-tree).
        #expect(queue.contains("docc-nav-list"))
        #expect(queue.contains("<summary>Protocols</summary>"))
        // Current-page highlighting is applied in the browser, so the static HTML
        // has no current marker but loads the script that adds it.
        #expect(!queue.contains("docc-current"))
        #expect(queue.contains("/_kiln/js/docc-nav.js"))
        // The script asset is emitted.
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("_kiln/js/docc-nav.js").path))
    }
}
