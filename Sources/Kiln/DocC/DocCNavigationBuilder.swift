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
        /// Whether the symbol is deprecated (struck through in the sidebar).
        var deprecated: Bool
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
            deprecated: entry.deprecated ?? false,
            children: (entry.children ?? []).map(convert)
        )
    }

    /// Render the sidebar HTML for a module — **once**, with no current-page
    /// state. Group markers start open; symbol branches start closed. The
    /// current page's highlighting and ancestor expansion are applied per page in
    /// the browser (`docc-nav.js`) by matching the link href to the URL, so the
    /// tree is built once per module instead of re-rendered for every page.
    ///
    /// - Parameter moduleTitle: the module's display name; rendered as a header
    ///   link to the module landing page at the top of the tree, so a reader can
    ///   return to the module home from any symbol without opening the module
    ///   switcher.
    func renderHTML(_ nodes: [Node], moduleTitle: String) -> String {
        guard !nodes.isEmpty else { return "" }
        var out = "<a class=\"docc-nav-home\" href=\"\(HTMLEscaping.attribute(urls.moduleRootURL))\">"
        out += HTMLEscaping.text(moduleTitle)
        out += "</a>\n"
        var idCounter = 0
        out += "<ul class=\"docc-nav-list\">\n"
        for node in nodes { out += render(node, idCounter: &idCounter) }
        out += "</ul>\n"
        return out
    }

    private func render(_ node: Node, idCounter: inout Int) -> String {
        let kindClass = "docc-kind-\(Self.sanitiseKind(node.kind))"
        let deprecatedClass = node.deprecated ? " docc-nav-deprecated" : ""
        var html = "<li class=\"docc-nav-item \(kindClass)\(deprecatedClass)\">"
        if node.isGroupMarker {
            // Category headers are always expanded and carry no link, so a plain
            // text <summary> disclosure is valid and needs no separate toggle.
            html += "<details class=\"docc-nav-group\" open>"
            html += "<summary>\(HTMLEscaping.text(node.title))</summary>\n"
            html += childList(node, id: nil, hidden: false, idCounter: &idCounter)
            html += "</details>"
        } else if !node.children.isEmpty {
            // A symbol that is both a link and a parent. The link and the
            // expand/collapse control must be *separate* interactive elements — a
            // link nested inside a <summary> is invalid and can't itself be
            // toggled — so the row pairs the link with a disclosure button that
            // controls a collapsible list. Starts collapsed; `docc-nav.js` opens
            // the current page's ancestor trail.
            idCounter += 1
            let listID = "docc-nav-\(idCounter)"
            html += "<div class=\"docc-nav-row\">"
            html += toggle(for: node, controls: listID)
            html += link(node)
            html += "</div>\n"
            html += childList(node, id: listID, hidden: true, idCounter: &idCounter)
        } else {
            html += link(node)
        }
        html += "</li>\n"
        return html
    }

    /// The collapsible list of a node's children. Symbol branches pass an `id`
    /// and `hidden: true` (a toggle button controls it); group markers pass
    /// `nil`/`false` (their native <details> handles visibility).
    private func childList(_ node: Node, id: String?, hidden: Bool, idCounter: inout Int) -> String {
        guard !node.children.isEmpty else { return "" }
        let idAttr = id.map { " id=\"\(HTMLEscaping.attribute($0))\"" } ?? ""
        var out = "<ul class=\"docc-nav-list\"\(idAttr)\(hidden ? " hidden" : "")>\n"
        for child in node.children { out += render(child, idCounter: &idCounter) }
        out += "</ul>\n"
        return out
    }

    /// Icon-only disclosure button that expands/collapses a branch's children.
    /// Carries an accessible label since it has no text; `docc-nav.js` flips
    /// `aria-expanded` and the controlled list's `hidden` state.
    private func toggle(for node: Node, controls: String) -> String {
        var out = "<button class=\"docc-nav-toggle\" type=\"button\" aria-expanded=\"false\""
        out += " aria-controls=\"\(HTMLEscaping.attribute(controls))\""
        out += " aria-label=\"Toggle \(HTMLEscaping.attribute(node.title))\">"
        out += "<span class=\"docc-nav-chevron\" aria-hidden=\"true\">"
        out += "<svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.25\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polyline points=\"9 6 15 12 9 18\"></polyline></svg>"
        out += "</span></button>"
        return out
    }

    private func link(_ node: Node) -> String {
        guard let url = node.url else { return HTMLEscaping.text(node.title) }
        return "<a class=\"docc-nav-link\" href=\"\(HTMLEscaping.attribute(url))\">\(HTMLEscaping.text(node.title))</a>"
    }

    /// Reduce a DocC entry type to a safe CSS-class suffix (alphanumerics only).
    static func sanitiseKind(_ kind: String) -> String {
        let cleaned = kind.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(cleaned).lowercased()
    }
}
