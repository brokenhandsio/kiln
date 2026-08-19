/// A navigation entry resolved for a specific language: titles translated,
/// URLs computed, ready to render.
public struct NavNode: Sendable {
    @nonexhaustive
    public enum Kind: String, Sendable {
        case page, section, link
    }

    public var kind: Kind
    public var title: String
    /// Absolute site URL for `page`/`link` nodes.
    public var url: String?
    /// The logical path for `page` nodes, used to match the current page.
    public var logicalPath: String?
    public var items: [NavNode]
    /// True for the page currently being rendered, or a section containing it.
    public var isActive: Bool
    /// True only for the exact current page.
    public var isCurrent: Bool

    init(kind: Kind, title: String, url: String? = nil, logicalPath: String? = nil, items: [NavNode] = []) {
        self.kind = kind
        self.title = title
        self.url = url
        self.logicalPath = logicalPath
        self.items = items
        self.isActive = false
        self.isCurrent = false
    }
}

/// A flattened reference to a navigable page, in document order, used for
/// previous/next links.
public struct NavPageRef: Sendable {
    public var title: String
    public var url: String
    public var logicalPath: String
}

/// A language's navigation: the tree plus the flattened page order.
public struct ResolvedNavigation: Sendable {
    public var nodes: [NavNode]
    public var orderedPages: [NavPageRef]
}

/// The navigation as seen from one page: nodes with active/current flags set,
/// plus previous/next links.
public struct PageNavigation: Sendable {
    public var nodes: [NavNode]
    public var previous: NavPageRef?
    public var next: NavPageRef?
}

/// Builds per-language navigation from the configured ``NavItem`` tree.
public struct NavigationBuilder: Sendable {
    private let urls: SiteURLs

    public init(urls: SiteURLs) {
        self.urls = urls
    }

    /// Resolve the configured navigation for a language: translate titles via
    /// `navTranslations` and compute locale-prefixed URLs.
    public func build(_ navigation: [NavItem], for language: Language) -> ResolvedNavigation {
        var ordered: [NavPageRef] = []
        let nodes = navigation.map { resolve($0, language: language, ordered: &ordered) }
        return ResolvedNavigation(nodes: nodes, orderedPages: ordered)
    }

    private func resolve(_ item: NavItem, language: Language, ordered: inout [NavPageRef]) -> NavNode {
        switch item {
        case .page(let title, let path):
            let translated = translate(title, language: language)
            let url = urls.urlPath(forLogicalPath: path, locale: language.locale)
            ordered.append(NavPageRef(title: translated, url: url, logicalPath: path))
            return NavNode(kind: .page, title: translated, url: url, logicalPath: path)
        case .section(let title, let items):
            let children = items.map { resolve($0, language: language, ordered: &ordered) }
            return NavNode(kind: .section, title: translate(title, language: language), items: children)
        case .link(let title, let url):
            return NavNode(kind: .link, title: translate(title, language: language), url: url)
        }
    }

    private func translate(_ title: String, language: Language) -> String {
        language.navTranslations[title] ?? title
    }

    /// Produce navigation for a specific page: mark the active trail and find
    /// the previous/next pages.
    public func contextualise(_ navigation: ResolvedNavigation, currentLogicalPath: String) -> PageNavigation {
        let nodes = navigation.nodes.map { mark($0, currentLogicalPath: currentLogicalPath) }

        var previous: NavPageRef?
        var next: NavPageRef?
        if let index = navigation.orderedPages.firstIndex(where: { $0.logicalPath == currentLogicalPath }) {
            if index > 0 { previous = navigation.orderedPages[index - 1] }
            if index < navigation.orderedPages.count - 1 { next = navigation.orderedPages[index + 1] }
        }
        return PageNavigation(nodes: nodes, previous: previous, next: next)
    }

    private func mark(_ node: NavNode, currentLogicalPath: String) -> NavNode {
        var node = node
        switch node.kind {
        case .page:
            node.isCurrent = node.logicalPath == currentLogicalPath
            node.isActive = node.isCurrent
        case .link:
            break
        case .section:
            node.items = node.items.map { mark($0, currentLogicalPath: currentLogicalPath) }
            node.isActive = node.items.contains { $0.isActive }
        }
        return node
    }
}
