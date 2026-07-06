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
