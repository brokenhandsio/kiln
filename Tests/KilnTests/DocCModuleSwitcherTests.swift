import Testing
@testable import Kiln

@Suite("DocC module switcher")
struct DocCModuleSwitcherTests {
    private func site() -> DocCSite {
        DocCSite(
            packages: [
                APIPackage("vapor/queues", ref: "main", group: "Queues", modules: [
                    Module("Queues"),
                    Module("XCTQueues", group: "Testing"),
                ]),
                APIPackage("vapor/fluent-kit", ref: "main", group: "Database", modules: [Module("FluentKit")]),
            ],
            groupOrder: ["Queues", "Database", "Testing"]
        )
    }

    @Test("Groups every module and marks the current one")
    func groupsCurrent() {
        let groups = DocCModuleSwitcher(docc: site(), basePath: "").groups(currentModule: "Queues")
        #expect(groups.map(\.title) == ["Queues", "Database", "Testing"])
        let all = groups.flatMap(\.modules)
        #expect(all.map(\.name) == ["Queues", "FluentKit", "XCTQueues"])
        #expect(all.filter(\.isCurrent).map(\.name) == ["Queues"])
        #expect(all.first { $0.name == "FluentKit" }?.url == "/fluentkit/")
    }

    @Test("Renders a details dropdown with the current module as the label")
    func rendersHTML() {
        let html = DocCModuleSwitcher(docc: site(), basePath: "").renderHTML(currentModule: "FluentKit")
        #expect(html.contains("<details class=\"docc-module-switcher\">"))
        #expect(html.contains("<span class=\"docc-module-current-name\">FluentKit</span>"))
        #expect(html.contains("<p class=\"docc-module-group\">Queues</p>"))
        #expect(html.contains("<a class=\"docc-module-link\" href=\"/queues/\">Queues</a>"))
        // The current module is flagged.
        #expect(html.contains("<a class=\"docc-module-link docc-current\" href=\"/fluentkit/\">FluentKit</a>"))
    }

    @Test("No current module → 'Modules' label, none flagged")
    func noCurrent() {
        let html = DocCModuleSwitcher(docc: site(), basePath: "").renderHTML(currentModule: nil)
        #expect(html.contains("<span class=\"docc-module-current-name\">Modules</span>"))
        #expect(!html.contains("docc-current"))
    }

    @Test("basePath prefixes the switcher URLs")
    func basePath() {
        let html = DocCModuleSwitcher(docc: site(), basePath: "/api").renderHTML(currentModule: "Queues")
        #expect(html.contains("href=\"/api/queues/\""))
    }
}
