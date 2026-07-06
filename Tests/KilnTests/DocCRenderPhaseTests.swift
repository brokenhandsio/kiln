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

        let output = fm.temporaryDirectory.appendingPathComponent("kiln-docc-output-\(UUID().uuidString)")
        let site = KilnSite(
            name: "Vapor API",
            url: "https://api.vapor.codes",
            llmsText: false,
            docc: DocCSite(packages: [
                APIPackage("vapor/queues", ref: "main", modules: [
                    Module("Queues", group: "Core"),
                    Module("XCTQueues", group: "Testing"),
                ]),
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
        // Landing hides the doc rails.
        #expect(index.contains("kiln-no-sidebar"))
    }

    @Test("Renders a symbol page with declaration, eyebrow, and TOC")
    func symbolPage() async throws {
        let output = try await buildSite()
        let queue = try html(output, "queues/queue/index.html")
        #expect(queue.contains("<h1>Queue</h1>"))
        #expect(queue.contains("docc-eyebrow"))          // role heading eyebrow
        #expect(queue.contains("<pre class=\"declaration\">"))
        // Curated Topics section for the protocol's members.
        #expect(queue.contains("Topics") || queue.contains("docc-topic"))
    }

    @Test("A method page's type references resolve to site URLs")
    func linksResolve() async throws {
        let output = try await buildSite()
        let method = try html(output, "queues/queue/dispatch(_:_:maxretrycount:delayuntil:id:)-630ll/index.html")
        #expect(method.contains("<h1>dispatch(_:_:maxRetryCount:delayUntil:id:)</h1>"))
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
        #expect(queue.contains("docc-module-switcher"))
        // The current module is the summary label and flagged in the list.
        #expect(queue.contains("<span class=\"docc-module-current-name\">Queues</span>"))
        #expect(queue.contains("<a class=\"docc-module-link docc-current\" href=\"/queues/\">Queues</a>"))
        // The sibling module is listed to switch to.
        #expect(queue.contains("href=\"/xctqueues/\">XCTQueues</a>"))
    }

    @Test("Every page carries the module sidebar, highlighting the current symbol")
    func sidebar() async throws {
        let output = try await buildSite()
        let queue = try html(output, "queues/queue/index.html")
        // The DocC sidebar is injected (not the empty nav-tree).
        #expect(queue.contains("docc-nav-list"))
        #expect(queue.contains("<summary>Protocols</summary>"))
        // The current page (Queue) is marked in the sidebar.
        #expect(queue.contains("docc-current"))
        #expect(queue.contains("aria-current=\"page\""))
    }
}
