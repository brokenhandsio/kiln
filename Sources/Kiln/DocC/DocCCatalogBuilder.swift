/// Builds the catalog landing page — the site root that links to every hosted
/// module, grouped by ``Module/group`` (with the package-level default applied),
/// ordered by ``DocCSite/groupOrder``.
///
/// Each module card links to the module's surfaced version — its default version,
/// or, for a module that only exists in a pre-release, that pre-release (flagged
/// with a badge). See ``APIPackage/surfacedModules``. The catalog is English-only
/// (single language) and rendered to HTML in Swift, like the rest of the output.
public struct DocCCatalogBuilder: Sendable {
    private let docc: DocCSite
    private let basePath: String

    public init(docc: DocCSite, basePath: String = "") {
        self.docc = docc
        self.basePath = basePath
    }

    /// One module card.
    public struct Entry: Sendable, Equatable {
        /// The module's target name (the archive key), for identity/current matching.
        public var name: String
        /// The display title (``Module/displayTitle``).
        public var title: String
        public var description: String?
        /// Site URL of the module's surfaced-version landing page (e.g. `/queues/`,
        /// or `/consolelogger/5-beta/` for a pre-release-only module).
        public var url: String
        /// A pill label when the module is surfaced at a pre-release (e.g. `"beta"`),
        /// else `nil`.
        public var badge: String?
    }

    /// A titled group of module cards.
    public struct Group: Sendable, Equatable {
        public var title: String
        public var entries: [Entry]
    }

    /// The grouped catalog. Groups are ordered by ``DocCSite/groupOrder`` first,
    /// then by first appearance, with the `"Other"` bucket (ungrouped modules)
    /// always last. Modules keep their declared order within a group.
    public func groups() -> [Group] {
        var appearance: [String] = []
        var byGroup: [String: [Entry]] = [:]

        for package in docc.packages {
            for (module, version) in package.surfacedModules {
                let groupName = package.group(for: module) ?? "Other"
                if byGroup[groupName] == nil {
                    appearance.append(groupName)
                    byGroup[groupName] = []
                }
                let urls = DocCURLs(moduleName: module.name, version: version, basePath: basePath)
                byGroup[groupName]?.append(Entry(
                    name: module.name,
                    title: module.displayTitle,
                    description: module.description,
                    url: urls.moduleRootURL,
                    badge: version.isPrerelease ? "beta" : nil
                ))
            }
        }

        var ordered: [String] = []
        for name in docc.groupOrder where byGroup[name] != nil { ordered.append(name) }
        for name in appearance where !ordered.contains(name) && name != "Other" { ordered.append(name) }
        if byGroup["Other"] != nil { ordered.append("Other") }

        return ordered.map { Group(title: $0, entries: byGroup[$0] ?? []) }
    }

    /// The catalog body HTML: a section of cards per group.
    public func renderHTML() -> String {
        var out = "<div class=\"docc-catalog\">\n"
        for group in groups() {
            out += "<section class=\"docc-catalog-group\">\n"
            out += "<h2 class=\"docc-catalog-group-title\">\(HTMLEscaping.text(group.title))</h2>\n"
            out += "<div class=\"docc-catalog-cards\">\n"
            for entry in group.entries {
                out += "<a class=\"docc-catalog-card\" href=\"\(HTMLEscaping.attribute(entry.url))\">\n"
                out += "<span class=\"docc-catalog-card-title\">\(HTMLEscaping.text(entry.title))"
                if let badge = entry.badge {
                    out += " <span class=\"docc-catalog-card-badge\">\(HTMLEscaping.text(badge))</span>"
                }
                out += "</span>\n"
                if let description = entry.description, !description.isEmpty {
                    out += "<span class=\"docc-catalog-card-desc\">\(HTMLEscaping.text(description))</span>\n"
                }
                out += "</a>\n"
            }
            out += "</div>\n</section>\n"
        }
        out += "</div>\n"
        return out
    }
}
