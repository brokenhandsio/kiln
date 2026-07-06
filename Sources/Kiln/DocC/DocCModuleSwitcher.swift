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

    /// The switcher HTML: a shared ``DocCSelect`` whose toggle shows the current
    /// module (or "Modules" on the catalog) and whose panel lists every module,
    /// grouped. Empty when there are no modules.
    func renderHTML(currentModule moduleName: String?) -> String {
        let groups = groups(currentModule: moduleName)
        let label = groups.flatMap(\.modules).first(where: \.isCurrent)?.name ?? "Modules"
        let sections = groups.map { group in
            DocCSelect.Section(
                title: group.title,
                options: group.modules.map { DocCSelect.Option(label: $0.name, url: $0.url, isCurrent: $0.isCurrent) }
            )
        }
        return DocCSelect.render(label: label, sections: sections, sizeClass: "docc-select--module")
    }
}
