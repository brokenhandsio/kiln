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
        DocCURLs(moduleName: "Queues", version: PackageVersion("default", ref: "main", isDefault: true))
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
        let html = builder.renderHTML(tree, currentPath: "/documentation/queues/queue")

        // Group markers are always-open disclosures with a plain summary.
        #expect(html.contains("<details class=\"docc-nav-group\" open>"))
        #expect(html.contains("<summary>Classes</summary>"))
        // A leaf symbol links to its site URL with an icon kind class.
        #expect(html.contains("docc-kind-protocol"))
        #expect(html.contains("href=\"/queues/queue/\""))
        // ScheduleBuilder (a class with members) is an expandable branch.
        #expect(html.contains("<details class=\"docc-nav-branch\""))
        #expect(html.contains("href=\"/queues/schedulebuilder/\""))
    }

    @Test("The current page is marked and its ancestors are opened")
    func highlightsCurrent() throws {
        let builder = DocCNavigationBuilder(urls: urls)
        let tree = builder.build(try queuesIndex())

        // A method nested under ScheduleBuilder → its branch opens and it's current.
        let current = "/documentation/queues/schedulebuilder/daily()"
        let html = builder.renderHTML(tree, currentPath: current)
        #expect(html.contains("aria-current=\"page\""))
        #expect(html.contains("docc-current"))
        // The ScheduleBuilder branch containing it is opened.
        #expect(html.contains("<details class=\"docc-nav-branch\" open>"))

        // On a page that isn't in the tree, nothing is marked current.
        let none = builder.renderHTML(tree, currentPath: "/documentation/queues/nonexistent")
        #expect(!none.contains("aria-current"))
    }

    @Test("A nil index yields an empty sidebar")
    func emptyIndex() {
        let builder = DocCNavigationBuilder(urls: urls)
        #expect(builder.build(nil).isEmpty)
        #expect(builder.renderHTML([], currentPath: "/x").isEmpty)
    }
}
