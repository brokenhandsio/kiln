import Testing
@testable import Kiln

@Suite("DocC version switcher")
struct DocCVersionSwitcherTests {
    private let v4 = PackageVersion("4", name: "4.x", ref: "v4", isDefault: true, modules: [Module("RoutingKit")])
    private let v5 = PackageVersion("5-beta", name: "5.0 (beta)", ref: "main", isPrerelease: true, modules: [Module("RoutingKit")])

    private func package() -> APIPackage {
        APIPackage("vapor/routing-kit", group: "Core", versions: [v4, v5])
    }

    /// v4 has /documentation/routingkit + /documentation/routingkit/router;
    /// v5-beta has the module root + a NEW symbol not present in v4.
    private func paths() -> [String: Set<String>] {
        [
            "4": ["/documentation/routingkit", "/documentation/routingkit/router"],
            "5-beta": ["/documentation/routingkit", "/documentation/routingkit/asyncrouter"],
        ]
    }

    private func switcher() -> DocCVersionSwitcher {
        DocCVersionSwitcher(package: package(), moduleName: "RoutingKit", basePath: "", pathsByVersion: paths())
    }

    @Test("A symbol present in both versions links to the same path in each")
    func sharedSymbol() {
        let options = switcher().options(currentVersion: v4, currentPath: "/documentation/routingkit/router")
        #expect(options.count == 2)
        // Default version (v4) → no version segment.
        let opt4 = options.first { $0.label == "4.x" }
        #expect(opt4?.url == "/routingkit/router/")
        #expect(opt4?.isCurrent == true)
        // v5-beta has no /router → falls back to its module landing, with a badge.
        let opt5 = options.first { $0.label == "5.0 (beta)" }
        #expect(opt5?.url == "/routingkit/5-beta/")   // fallback (router absent in v5)
        #expect(opt5?.isCurrent == false)
        #expect(opt5?.badge == "beta")
    }

    @Test("A symbol only in the target version resolves to its full path")
    func targetOnlySymbol() {
        // Viewing v5-beta's asyncrouter; switching to v4 (which lacks it) falls back.
        let options = switcher().options(currentVersion: v5, currentPath: "/documentation/routingkit/asyncrouter")
        #expect(options.first { $0.label == "5.0 (beta)" }?.url == "/routingkit/5-beta/asyncrouter/")
        #expect(options.first { $0.label == "4.x" }?.url == "/routingkit/")   // v4 fallback
    }

    @Test("The module landing resolves in every version")
    func moduleLanding() {
        let options = switcher().options(currentVersion: v4, currentPath: "/documentation/routingkit")
        #expect(options.first { $0.label == "4.x" }?.url == "/routingkit/")
        #expect(options.first { $0.label == "5.0 (beta)" }?.url == "/routingkit/5-beta/")
    }

    @Test("Renders a shared docc-select flagged to the current version")
    func rendersHTML() {
        let html = switcher().renderHTML(currentVersion: v4, currentPath: "/documentation/routingkit/router")
        #expect(html.contains("<details class=\"docc-select docc-select--version\">"))
        #expect(html.contains("<span class=\"docc-select-value\">4.x</span>"))
        #expect(html.contains("<a class=\"docc-select-option is-current\" href=\"/routingkit/router/\">4.x</a>"))
        #expect(html.contains("5.0 (beta) <span class=\"docc-select-badge\">beta</span>"))
        // Purpose-stating accessible name that includes the visible value (WCAG 2.5.3).
        #expect(html.contains("<summary class=\"docc-select-toggle\" aria-label=\"Select version: 4.x\">"))
    }

    @Test("A single-version package renders no version switcher")
    func singleVersion() {
        let single = APIPackage("vapor/queues", versions: [.single(ref: "main", modules: [Module("Queues")])])
        let sw = DocCVersionSwitcher(package: single, moduleName: "Queues", basePath: "",
                                     pathsByVersion: ["default": ["/documentation/queues"]])
        #expect(sw.renderHTML(currentVersion: single.defaultVersion, currentPath: "/documentation/queues").isEmpty)
    }
}
