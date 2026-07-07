import Testing
import Foundation
@testable import Kiln

/// Exercises incremental DocC builds: unchanged modules are reused, a changed
/// archive re-renders just its module, and a template change forces a full build.
@Suite("DocC incremental build")
struct DocCIncrementalTests {
    /// A DocC-only site over a temp content dir, with a copy of the Queues +
    /// XCTQueues fixtures under `archives/default/`.
    private func makeProject() throws -> (content: URL, output: URL) {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        let docc = fixtures.appendingPathComponent("docc")
        let fm = FileManager.default
        let content = fm.temporaryDirectory.appendingPathComponent("kiln-incr-\(UUID().uuidString)")
        let archives = content.appendingPathComponent("archives/default")
        try fm.createDirectory(at: archives, withIntermediateDirectories: true)
        for module in ["Queues", "XCTQueues"] {
            try fm.copyItem(at: docc.appendingPathComponent("\(module).doccarchive"),
                            to: archives.appendingPathComponent("\(module).doccarchive"))
        }
        let output = fm.temporaryDirectory.appendingPathComponent("kiln-incr-out-\(UUID().uuidString)")
        return (content, output)
    }

    private func site() -> KilnSite {
        KilnSite(name: "API", url: "https://api.example.com", llmsText: false,
                 docc: DocCSite(packages: [
                    APIPackage("vapor/queues", ref: "main", modules: [Module("Queues"), Module("XCTQueues")]),
                 ]))
    }

    private func build(_ content: URL, _ output: URL) async throws {
        try await Kiln.build(site(), contentDirectory: content, outputDirectory: output,
                             linkChecking: .off, incremental: true)
    }

    private func mtime(_ url: URL) -> Date? {
        // Read via FileManager (URL.resourceValues caches on the URL instance,
        // which would mask a rewrite when the same URL is reused).
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    @Test("Second build with no changes reuses unchanged modules (pages not rewritten)")
    func reusesUnchanged() async throws {
        let (content, output) = try makeProject()
        try await build(content, output)

        let queuePage = output.appendingPathComponent("queues/queue/index.html")
        let firstMtime = mtime(queuePage)
        #expect(firstMtime != nil)
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("_kiln/docc-manifest.json").path))

        // Rebuild with nothing changed → the page file is left untouched.
        try await Task.sleep(nanoseconds: 1_100_000_000) // ensure a distinguishable mtime if rewritten
        try await build(content, output)
        #expect(mtime(queuePage) == firstMtime, "unchanged module's page should not be rewritten")

        // Even though both modules were skipped, the regenerated sitemap still
        // lists their pages (it's assembled from the persisted search fragments).
        let sitemap = try String(contentsOf: output.appendingPathComponent("sitemap.xml"), encoding: .utf8)
        #expect(sitemap.contains("<loc>https://api.example.com/queues/queue/</loc>"))
        #expect(sitemap.contains("<loc>https://api.example.com/xctqueues/</loc>"))
    }

    @Test("Changing one archive re-renders only that module")
    func rerendersChangedModule() async throws {
        let (content, output) = try makeProject()
        try await build(content, output)

        let queuePage = output.appendingPathComponent("queues/queue/index.html")
        let xctPage = output.appendingPathComponent("xctqueues/index.html")
        let queueMtime = mtime(queuePage)
        let xctMtime = mtime(xctPage)

        try await Task.sleep(nanoseconds: 1_100_000_000)
        // "Change" the Queues archive by touching one of its data files.
        let dataFile = content.appendingPathComponent("archives/default/Queues.doccarchive/data/documentation/queues.json")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: dataFile.path)

        try await build(content, output)
        #expect(mtime(queuePage) != queueMtime, "changed module should be re-rendered")
        #expect(mtime(xctPage) == xctMtime, "untouched module should be reused")
    }

    @Test("Removing a module deletes its output")
    func removesDroppedModule() async throws {
        let (content, output) = try makeProject()
        try await build(content, output)
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("xctqueues").path))

        // Rebuild with only Queues configured.
        let trimmed = KilnSite(name: "API", url: "https://api.example.com", llmsText: false,
                               docc: DocCSite(packages: [APIPackage("vapor/queues", ref: "main", modules: [Module("Queues")])]))
        try await Kiln.build(trimmed, contentDirectory: content, outputDirectory: output, linkChecking: .off, incremental: true)
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("xctqueues").path),
                "dropped module's output should be removed")
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("queues").path))
    }
}
