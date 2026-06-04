import Foundation

/// A single markdown source file in one language.
public struct ContentPage: Sendable {
    /// The canonical, locale-independent path relative to the content directory,
    /// e.g. `"install/macos.md"`. Navigation entries reference this path.
    public var logicalPath: String
    /// The locale this file provides content for.
    public var locale: String
    /// The file on disk.
    public var sourceURL: URL
    /// Parsed front matter (may be empty).
    public var frontMatter: FrontMatter
    /// The markdown body with any front matter stripped.
    public var body: String

    public init(logicalPath: String, locale: String, sourceURL: URL, frontMatter: FrontMatter, body: String) {
        self.logicalPath = logicalPath
        self.locale = locale
        self.sourceURL = sourceURL
        self.frontMatter = frontMatter
        self.body = body
    }

    /// Whether this is the site's home page.
    public var isHome: Bool {
        logicalPath == "index.md"
    }
}

/// All loaded content, indexed by logical path and locale, with fallback lookup.
public struct ContentStore: Sendable {
    /// `logicalPath -> (locale -> Page)`.
    private var pages: [String: [String: ContentPage]]

    init(pages: [String: [String: ContentPage]]) {
        self.pages = pages
    }

    /// Look up a page for a logical path in a given locale, falling back to the
    /// default locale when the translation is missing.
    public func page(forLogicalPath path: String, locale: String, defaultLocale: String) -> ContentPage? {
        let byLocale = pages[path]
        return byLocale?[locale] ?? byLocale?[defaultLocale]
    }

    /// Whether a translation exists for this logical path in this exact locale
    /// (no fallback).
    public func hasTranslation(forLogicalPath path: String, locale: String) -> Bool {
        pages[path]?[locale] != nil
    }

    /// All logical paths that have any content.
    public var logicalPaths: [String] {
        Array(pages.keys)
    }
}
