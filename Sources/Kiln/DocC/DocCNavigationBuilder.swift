/// Builds a module's sidebar navigation from its ``RenderIndex`` (the archive's
/// `index/index.json`).
///
/// DocC navigation is deeply nested and mixes non-navigable group markers
/// ("Classes", "Structures", …) with symbols that are *both* links and
/// expandable (a class with its methods). Kiln's built-in `nav-tree` partial is
/// hand-unrolled to a fixed depth and can't express that, so — as with DocC page
/// content — the sidebar is rendered to HTML in Swift and injected into the
/// theme (`nav.doccHTML`).
///
/// The tree is parsed once per module (``build(_:)``); the current-page
/// highlighting and ancestor expansion are applied per page (``renderHTML(_:currentPath:)``).
public struct DocCNavigationBuilder: Sendable {
    private let urls: DocCURLs

    public init(urls: DocCURLs) {
        self.urls = urls
    }

    /// A parsed sidebar node (module children flattened to the nav roots).
    struct Node: Sendable {
        var title: String
        /// Site URL, or `nil` for a non-navigable group marker.
        var url: String?
        /// The archive path, for matching the current page.
        var path: String?
        /// The DocC entry type (`class`, `struct`, `groupMarker`, …) → icon class.
        var kind: String
        var isGroupMarker: Bool
        var children: [Node]
    }

    /// Parse the navigation roots from an index. The single module entry at the
    /// top is unwrapped — its children (the groups and top-level symbols) become
    /// the sidebar roots.
    func build(_ index: RenderIndex?) -> [Node] {
        guard let index else { return [] }
        let roots = index.interfaceLanguages["swift"] ?? index.interfaceLanguages.values.first ?? []
        return roots.flatMap { root in (root.children ?? []).map(convert) }
    }

    private func convert(_ entry: RenderIndex.Entry) -> Node {
        Node(
            title: entry.title,
            url: entry.path.map { urls.url(forDocCPath: $0) },
            path: entry.path,
            kind: entry.type,
            isGroupMarker: entry.isGroupMarker,
            children: (entry.children ?? []).map(convert)
        )
    }

    /// Render the sidebar HTML for a page, marking the entry whose path matches
    /// `currentPath` as current and opening the disclosure of every ancestor.
    func renderHTML(_ nodes: [Node], currentPath: String) -> String {
        guard !nodes.isEmpty else { return "" }
        var out = "<ul class=\"docc-nav-list\">\n"
        for node in nodes { out += render(node, currentPath: currentPath).html }
        out += "</ul>\n"
        return out
    }

    /// Render one node, returning its HTML and whether it (or a descendant) is the
    /// current page — used to open the ancestor disclosures.
    private func render(_ node: Node, currentPath: String) -> (html: String, active: Bool) {
        let isCurrent = node.path == currentPath
        var active = isCurrent

        var childrenHTML = ""
        if !node.children.isEmpty {
            childrenHTML = "<ul class=\"docc-nav-list\">\n"
            for child in node.children {
                let result = render(child, currentPath: currentPath)
                childrenHTML += result.html
                if result.active { active = true }
            }
            childrenHTML += "</ul>\n"
        }

        let kindClass = "docc-kind-\(Self.sanitiseKind(node.kind))"
        var html = "<li class=\"docc-nav-item \(kindClass)\">"
        if node.isGroupMarker {
            // Category headers are always expanded; they carry no link.
            html += "<details class=\"docc-nav-group\" open>"
            html += "<summary>\(HTMLEscaping.text(node.title))</summary>\n"
            html += childrenHTML
            html += "</details>"
        } else if !node.children.isEmpty {
            // A symbol that is both a link and a parent: open when on the trail.
            html += "<details class=\"docc-nav-branch\"\(active ? " open" : "")>"
            html += "<summary>\(link(node, isCurrent: isCurrent))</summary>\n"
            html += childrenHTML
            html += "</details>"
        } else {
            html += link(node, isCurrent: isCurrent)
        }
        html += "</li>\n"
        return (html, active)
    }

    private func link(_ node: Node, isCurrent: Bool) -> String {
        guard let url = node.url else { return HTMLEscaping.text(node.title) }
        let currentClass = isCurrent ? " docc-current" : ""
        let currentAttr = isCurrent ? " aria-current=\"page\"" : ""
        return "<a class=\"docc-nav-link\(currentClass)\" href=\"\(HTMLEscaping.attribute(url))\"\(currentAttr)>\(HTMLEscaping.text(node.title))</a>"
    }

    /// Reduce a DocC entry type to a safe CSS-class suffix (alphanumerics only).
    static func sanitiseKind(_ kind: String) -> String {
        let cleaned = kind.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(cleaned).lowercased()
    }
}
