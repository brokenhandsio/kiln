import Testing
import Foundation
@testable import Kiln

@Suite("DocC sidebar navigation")
struct DocCNavigationTests {
    private func queuesIndex() throws -> RenderIndex {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        let file = fixtures.appendingPathComponent("docc/Queues.doccarchive/index/index.json")
        return try JSONDecoder().decode(RenderIndex.self, from: Data(contentsOf: file))
    }

    private var urls: DocCURLs {
        DocCURLs(moduleName: "Queues", version: PackageVersion("default", ref: "main", isDefault: true, modules: []))
    }

    @Test("Builds the sidebar tree from the module's children (groups + symbols)")
    func buildsTree() throws {
        let builder = DocCNavigationBuilder(urls: urls)
        let tree = builder.build(try queuesIndex())
        #expect(!tree.isEmpty)
        // The top module entry is unwrapped: roots are its group markers.
        #expect(tree.contains { $0.isGroupMarker && $0.title == "Classes" })
        #expect(tree.contains { $0.isGroupMarker && $0.title == "Protocols" })
    }

    @Test("Renders groups, symbol links, and expandable branches")
    func rendersHTML() throws {
        let builder = DocCNavigationBuilder(urls: urls)
        let tree = builder.build(try queuesIndex())
        let html = builder.renderHTML(tree)

        // Group markers are always-open disclosures with a plain summary.
        #expect(html.contains("<details class=\"docc-nav-group\" open>"))
        #expect(html.contains("<summary>Classes</summary>"))
        // A leaf symbol links to its site URL with an icon kind class.
        #expect(html.contains("docc-kind-protocol"))
        #expect(html.contains("href=\"/queues/queue/\""))
        // ScheduleBuilder (a class with members) is an expandable branch, rendered
        // closed — the browser (docc-nav.js) opens the current trail.
        #expect(html.contains("<details class=\"docc-nav-branch\">"))
        #expect(html.contains("href=\"/queues/schedulebuilder/\""))
    }

    @Test("The tree is rendered once with no per-page current state")
    func staticTree() throws {
        let builder = DocCNavigationBuilder(urls: urls)
        let tree = builder.build(try queuesIndex())
        let html = builder.renderHTML(tree)
        // Highlighting is applied client-side, so the static HTML carries no
        // current markers and symbol branches are closed.
        #expect(!html.contains("aria-current"))
        #expect(!html.contains("docc-current"))
        #expect(!html.contains("docc-nav-branch\" open"))
    }

    @Test("A nil index yields an empty sidebar")
    func emptyIndex() {
        let builder = DocCNavigationBuilder(urls: urls)
        #expect(builder.build(nil).isEmpty)
        #expect(builder.renderHTML([]).isEmpty)
    }
}
