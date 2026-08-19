/// An entry in the site navigation tree.
///
/// Build the tree with the ``Page(_:_:)``, ``Section(_:_:)`` and
/// ``Link(_:_:)`` helpers inside a ``NavBuilder`` closure:
///
/// ```swift
/// navigation: {
///     Page("Welcome", "index.md")
///     Section("Install") {
///         Page("macOS", "install/macos.md")
///         Page("Linux", "install/linux.md")
///     }
///     Link("API Docs", "https://api.vapor.codes")
/// }
/// ```
@nonexhaustive
public indirect enum NavItem: Sendable {
    /// A documentation page backed by a markdown file (path relative to the
    /// content directory).
    case page(title: String, path: String)
    /// A collapsible group of nav items.
    case section(title: String, items: [NavItem])
    /// An external link.
    case link(title: String, url: String)

    /// The (default-language) title used for display and as the key for
    /// `navTranslations` lookups.
    public var title: String {
        switch self {
        case .page(let title, _): return title
        case .section(let title, _): return title
        case .link(let title, _): return title
        }
    }
}

/// A documentation page backed by a markdown file.
public func Page(_ title: String, _ path: String) -> NavItem {
    .page(title: title, path: path)
}

/// A collapsible navigation section.
public func Section(_ title: String, @NavBuilder _ items: () -> [NavItem]) -> NavItem {
    .section(title: title, items: items())
}

/// An external navigation link.
public func Link(_ title: String, _ url: String) -> NavItem {
    .link(title: title, url: url)
}

/// Result builder for assembling a ``NavItem`` tree.
@resultBuilder
public enum NavBuilder {
    public static func buildBlock(_ components: [NavItem]...) -> [NavItem] {
        components.flatMap { $0 }
    }
    public static func buildExpression(_ expression: NavItem) -> [NavItem] {
        [expression]
    }
    public static func buildExpression(_ expression: [NavItem]) -> [NavItem] {
        expression
    }
    public static func buildOptional(_ component: [NavItem]?) -> [NavItem] {
        component ?? []
    }
    public static func buildEither(first component: [NavItem]) -> [NavItem] {
        component
    }
    public static func buildEither(second component: [NavItem]) -> [NavItem] {
        component
    }
    public static func buildArray(_ components: [[NavItem]]) -> [NavItem] {
        components.flatMap { $0 }
    }
}
