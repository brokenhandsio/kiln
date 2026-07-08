import Testing
import Foundation
@testable import Kiln

@Suite("DocC catalog")
struct DocCCatalogTests {
    private func site() -> DocCSite {
        let vapor = Module("Vapor", description: "Core web framework")
        let xctVapor = Module("XCTVapor", group: "Testing")
        return DocCSite(
            packages: [
                APIPackage("vapor/vapor", group: "Core", versions: [
                    PackageVersion("4", ref: "vapor-4", isDefault: true, modules: [vapor, xctVapor]),
                    PackageVersion("5-alpha", ref: "main", isPrerelease: true, modules: [vapor, xctVapor]),
                ]),
                APIPackage("vapor/fluent-kit", group: "Database",
                           versions: [.single(ref: "main", modules: [Module("FluentKit")])]),
                APIPackage("vapor/leaf-kit",
                           versions: [.single(ref: "main", modules: [Module("LeafKit")])]), // no group → Other
            ],
            groupOrder: ["Core", "Database"]
        )
    }

    @Test("Groups ordered by groupOrder, then appearance, then Other last")
    func grouping() {
        let groups = DocCCatalogBuilder(docc: site()).groups()
        #expect(groups.map(\.title) == ["Core", "Database", "Testing", "Other"])
    }

    @Test("Cards carry title/description and link to the module's default version")
    func cards() {
        let groups = DocCCatalogBuilder(docc: site()).groups()
        let core = try? #require(groups.first { $0.title == "Core" })

        let vapor = core?.entries.first { $0.title == "Vapor" }
        #expect(vapor?.description == "Core web framework")
        // Default version (v4) → no version segment in the URL.
        #expect(vapor?.url == "/vapor/")

        // XCTVapor's own group overrides the package default group.
        let testing = groups.first { $0.title == "Testing" }
        #expect(testing?.entries.map(\.title) == ["XCTVapor"])
        #expect(testing?.entries.first?.url == "/xctvapor/")

        // Ungrouped module falls into Other.
        let other = groups.first { $0.title == "Other" }
        #expect(other?.entries.map(\.title) == ["LeafKit"])
    }

    @Test("A pre-release-only module surfaces at its pre-release, badged")
    func prereleaseOnlyModule() throws {
        let consoleKit = Module("ConsoleKit")
        let consoleLogger = Module("ConsoleLogger", description: "Console log handler.")
        let site = DocCSite(packages: [
            APIPackage("vapor/console-kit", group: "Core", versions: [
                PackageVersion("4", ref: "v4", isDefault: true, modules: [consoleKit]),
                PackageVersion("5-beta", ref: "main", isPrerelease: true, modules: [consoleKit, consoleLogger]),
            ]),
        ])
        let core = try #require(DocCCatalogBuilder(docc: site).groups().first { $0.title == "Core" })

        let ck = core.entries.first { $0.title == "ConsoleKit" }
        #expect(ck?.url == "/consolekit/")   // default version, no badge
        #expect(ck?.badge == nil)

        // ConsoleLogger only exists in the beta → surfaced there, with a badge.
        let cl = core.entries.first { $0.title == "ConsoleLogger" }
        #expect(cl?.url == "/consolelogger/5-beta/")
        #expect(cl?.badge == "beta")

        let html = DocCCatalogBuilder(docc: site).renderHTML()
        #expect(html.contains("<a class=\"docc-catalog-card\" href=\"/consolelogger/5-beta/\">"))
        #expect(html.contains("<span class=\"docc-catalog-card-badge\">beta</span>"))
    }

    @Test("basePath prefixes card URLs")
    func basePath() {
        let groups = DocCCatalogBuilder(docc: site(), basePath: "/api").groups()
        let vapor = groups.first { $0.title == "Core" }?.entries.first { $0.title == "Vapor" }
        #expect(vapor?.url == "/api/vapor/")
    }

    @Test("Rendered HTML has grouped cards linking to modules")
    func html() {
        let html = DocCCatalogBuilder(docc: site()).renderHTML()
        #expect(html.contains("<h2 class=\"docc-catalog-group-title\">Core</h2>"))
        #expect(html.contains("<a class=\"docc-catalog-card\" href=\"/vapor/\">"))
        #expect(html.contains("<span class=\"docc-catalog-card-title\">Vapor</span>"))
        #expect(html.contains("Core web framework"))
        // Group order is reflected in the markup.
        let coreIdx = html.range(of: ">Core</h2>")!.lowerBound
        let otherIdx = html.range(of: ">Other</h2>")!.lowerBound
        #expect(coreIdx < otherIdx)
    }
}
