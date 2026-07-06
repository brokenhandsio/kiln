/// One module entry in the module switcher.
public struct DocCModuleLink: Sendable, Equatable {
    /// Display title.
    public var name: String
    /// Site URL of the module's default-version landing page.
    public var url: String
    /// Whether this is the module currently being viewed.
    public var isCurrent: Bool
}

/// A titled group of modules in the switcher (same grouping as the catalog).
public struct DocCModuleGroup: Sendable, Equatable {
    public var title: String
    public var modules: [DocCModuleLink]
}

/// Builds the module-switcher data: every hosted module, grouped and ordered like
/// the catalog, with the current module flagged. Switching lands on the target
/// module's default-version landing page.
///
/// (Per-package *version* switching is layered on separately; this covers module
/// switching only.)
struct DocCModuleSwitcher: Sendable {
    let docc: DocCSite
    let basePath: String

    /// The grouped modules, marking `currentModule` (by target name) as current.
    func groups(currentModule: String?) -> [DocCModuleGroup] {
        DocCCatalogBuilder(docc: docc, basePath: basePath).groups().map { group in
            DocCModuleGroup(
                title: group.title,
                modules: group.entries.map { entry in
                    DocCModuleLink(name: entry.title, url: entry.url, isCurrent: entry.name == currentModule)
                }
            )
        }
    }

    /// The switcher HTML: a `<details>` disclosure whose summary shows the current
    /// module (or "Modules" on the catalog) and whose panel lists every module,
    /// grouped. Rendered in Swift (like the sidebar nav) so every theme injects
    /// the same markup; CSS styles it. Empty when there are no modules.
    func renderHTML(currentModule moduleName: String?) -> String {
        let groups = groups(currentModule: moduleName)
        guard !groups.isEmpty else { return "" }
        let label = groups.flatMap(\.modules).first(where: \.isCurrent)?.name ?? "Modules"

        var out = "<details class=\"docc-module-switcher\">\n"
        out += "<summary class=\"docc-module-current\" aria-label=\"Select module\">"
        out += "<span class=\"docc-module-current-name\">\(HTMLEscaping.text(label))</span>"
        out += "<span class=\"vapor-icon icon-chevron-down docc-module-chevron\" aria-hidden=\"true\"></span>"
        out += "</summary>\n<div class=\"docc-module-menu\">\n"
        for group in groups {
            out += "<p class=\"docc-module-group\">\(HTMLEscaping.text(group.title))</p>\n"
            for module in group.modules {
                let currentClass = module.isCurrent ? " docc-current" : ""
                out += "<a class=\"docc-module-link\(currentClass)\" href=\"\(HTMLEscaping.attribute(module.url))\">\(HTMLEscaping.text(module.name))</a>\n"
            }
        }
        out += "</div>\n</details>\n"
        return out
    }
}
