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
        let html = builder.renderHTML(tree, moduleTitle: "Queues")

        // A module-home header links back to the module landing from any page.
        #expect(html.contains("<a class=\"docc-nav-home\" href=\"/queues/\">Queues</a>"))
        // Group markers are always-open disclosures with a plain summary.
        #expect(html.contains("<details class=\"docc-nav-group\" open>"))
        #expect(html.contains("<summary>Classes</summary>"))
        // A leaf symbol links to its site URL with an icon kind class.
        #expect(html.contains("docc-kind-protocol"))
        #expect(html.contains("href=\"/queues/queue/\""))
        // ScheduleBuilder (a class with members) is an expandable branch: its
        // link is paired with a separate disclosure button controlling a hidden
        // child list, rendered collapsed — the browser (docc-nav.js) opens the
        // current trail. (A link inside a <summary> would be invalid.)
        #expect(html.contains("<div class=\"docc-nav-row\">"))
        #expect(html.contains("<button class=\"docc-nav-toggle\" type=\"button\" aria-expanded=\"false\""))
        #expect(html.contains("aria-label=\"Toggle ScheduleBuilder\""))
        #expect(html.contains("<ul class=\"docc-nav-list\" id=\"docc-nav-"))
        #expect(html.contains("href=\"/queues/schedulebuilder/\""))
    }

    @Test("The tree is rendered once with no per-page current state")
    func staticTree() throws {
        let builder = DocCNavigationBuilder(urls: urls)
        let tree = builder.build(try queuesIndex())
        let html = builder.renderHTML(tree, moduleTitle: "Queues")
        // Highlighting is applied client-side, so the static HTML carries no
        // current markers and symbol branches are collapsed (toggles not expanded,
        // child lists hidden).
        #expect(!html.contains("aria-current"))
        #expect(!html.contains("docc-current"))
        #expect(!html.contains("aria-expanded=\"true\""))
        #expect(html.contains("<ul class=\"docc-nav-list\" id=\"docc-nav-1\" hidden>"))
    }

    @Test("A nil index yields an empty sidebar")
    func emptyIndex() {
        let builder = DocCNavigationBuilder(urls: urls)
        #expect(builder.build(nil).isEmpty)
        #expect(builder.renderHTML([], moduleTitle: "Queues").isEmpty)
    }
}
