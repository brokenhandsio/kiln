import Testing
import Foundation
@testable import Kiln

/// Exercises ``DocCArchiveLoader`` against the checked-in Queues/XCTQueues
/// archives: identity, page counts, the navigation index, the link-resolution
/// lookups, and clean loading (no unknown constructs, no load issues).
@Suite("DocC archive loading")
struct DocCArchiveLoaderTests {
    private func archive(_ name: String) throws -> URL {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            Issue.record("Could not locate the Fixtures resource")
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        return fixtures.appendingPathComponent("docc/\(name).doccarchive")
    }

    @Test("Loads the Queues archive: identity, pages, index, clean")
    func loadsQueues() throws {
        let diagnostics = DocCDiagnostics()
        let archive = try DocCArchiveLoader().load(archiveURL: try archive("Queues"), diagnostics: diagnostics)

        #expect(archive.moduleName == "Queues")
        #expect(archive.bundleID == "Queues")
        #expect(archive.pages.count == 292)
        #expect(archive.index != nil)
        #expect(archive.loadIssues.isEmpty, "unexpected load issues: \(archive.loadIssues)")
        #expect(diagnostics.unknowns.isEmpty, "unexpected unknown constructs: \(diagnostics.summary)")

        // Pages are sorted by path for deterministic output.
        #expect(archive.pages.map(\.path) == archive.pages.map(\.path).sorted())
    }

    @Test("Loads the XCTQueues archive")
    func loadsXCTQueues() throws {
        let diagnostics = DocCDiagnostics()
        let archive = try DocCArchiveLoader().load(archiveURL: try archive("XCTQueues"), diagnostics: diagnostics)
        #expect(archive.moduleName == "XCTQueues")
        #expect(archive.pages.count == 15)
        #expect(archive.loadIssues.isEmpty)
        #expect(diagnostics.unknowns.isEmpty)
    }

    @Test("Resolves pages by URL path and by doc:// identifier")
    func lookups() throws {
        let archive = try DocCArchiveLoader().load(archiveURL: try archive("Queues"))

        // By archive-relative path (as carried in references' `url`).
        let landing = try #require(archive.pagesByPath["/documentation/queues"])
        #expect(landing.identifier == "doc://Queues/documentation/Queues")
        let queue = try #require(archive.pagesByPath["/documentation/queues/queue"])
        #expect(queue.node.metadata.symbolKind == "protocol")

        // By doc:// identifier (as listed in topic/relationship sections).
        let byID = try #require(archive.pagesByIdentifier["doc://Queues/documentation/Queues/JobIdentifier"])
        #expect(byID.path == "/documentation/queues/jobidentifier")
        #expect(byID.node.metadata.symbolKind == "struct")

        // The landing-page convenience.
        #expect(archive.landingPage?.path == "/documentation/queues")
    }

    @Test("A page's topic-section members resolve to hosted pages")
    func topicMembersResolve() throws {
        let archive = try DocCArchiveLoader().load(archiveURL: try archive("Queues"))
        let landing = try #require(archive.landingPage)
        let groups = try #require(landing.node.topicSections)
        // Every curated topic identifier on the landing page is a page we host
        // (Queues curates only its own symbols on the landing page).
        var checked = 0
        for group in groups {
            for identifier in group.identifiers {
                #expect(archive.pagesByIdentifier[identifier] != nil, "unresolved topic member: \(identifier)")
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    @Test("The navigation index roots at the module")
    func indexRoot() throws {
        let archive = try DocCArchiveLoader().load(archiveURL: try archive("Queues"))
        let index = try #require(archive.index)
        let roots = try #require(index.interfaceLanguages["swift"])
        #expect(roots.first?.title == "Queues")
        #expect(roots.first?.type == "module")
    }

    @Test("A missing archive throws, not crashes")
    func missingArchive() {
        let bogus = URL(fileURLWithPath: "/nonexistent/Nope.doccarchive")
        #expect(throws: DocCArchiveError.self) {
            _ = try DocCArchiveLoader().load(archiveURL: bogus)
        }
    }
}
