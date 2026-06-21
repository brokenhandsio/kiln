#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Computes the output paths and site-relative URLs for pages, applying the
/// pretty-URL ("directory") scheme and per-locale prefixing.
///
/// The default language is built at the site root; other locales live under
/// `/<locale>/`. This mirrors mkdocs-static-i18n's suffix layout.
public struct SiteURLs: Sendable {
    public let defaultLocale: String
    /// The version URL prefix, including a trailing slash when set (e.g.
    /// `"4.0/"`), or `""` for the default version (served at the root).
    public let versionPrefix: String
    /// The path the whole site is mounted at, normalised to a leading slash and
    /// no trailing slash (e.g. `"/docs"`), or `""` when served from the domain
    /// root. Prefixed onto every root-relative URL so links resolve when the
    /// site lives in a subdirectory.
    public let basePath: String

    public init(defaultLocale: String, versionPrefix: String = "", basePath: String = "") {
        self.defaultLocale = defaultLocale
        self.versionPrefix = versionPrefix
        self.basePath = SiteURLs.normaliseBasePath(basePath)
    }

    /// Normalise a configured base path to a leading slash with no trailing
    /// slash: `"docs"`, `"/docs"`, and `"/docs/"` all become `"/docs"`; an empty
    /// path (or `"/"`) becomes `""` (served from the domain root).
    public static func normaliseBasePath(_ raw: String) -> String {
        var path = raw
        while path.hasPrefix("/") { path.removeFirst() }
        while path.hasSuffix("/") { path.removeLast() }
        return path.isEmpty ? "" : "/" + path
    }

    /// The pretty, locale-independent path for a logical path:
    /// `"install/macos.md"` → `"install/macos/"`, `"index.md"` → `""`,
    /// `"advanced/index.md"` → `"advanced/"`.
    func prettyPath(forLogicalPath logicalPath: String) -> String {
        var path = logicalPath
        if path.hasSuffix(".md") {
            path.removeLast(3)
        }
        if path == "index" {
            return ""
        }
        if path.hasSuffix("/index") {
            path.removeLast(6) // drop "/index", keep trailing slash below
        }
        return path.isEmpty ? "" : path + "/"
    }

    private func localePrefix(_ locale: String) -> String {
        locale == defaultLocale ? "" : locale + "/"
    }

    /// The absolute, site-relative URL for a page, e.g. `/4.0/de/install/macos/`
    /// (prefixed with ``basePath`` when the site is mounted in a subdirectory).
    public func urlPath(forLogicalPath logicalPath: String, locale: String) -> String {
        basePath + "/" + versionPrefix + localePrefix(locale) + prettyPath(forLogicalPath: logicalPath)
    }

    /// The on-disk output file for a page (`…/install/macos/index.html`).
    public func outputFile(forLogicalPath logicalPath: String, locale: String, in outputDirectory: URL) -> URL {
        var url = outputDirectory
        for component in versionPrefix.split(separator: "/") {
            url.appendPathComponent(String(component), isDirectory: true)
        }
        if locale != defaultLocale {
            url.appendPathComponent(locale, isDirectory: true)
        }
        let pretty = prettyPath(forLogicalPath: logicalPath)
        for component in pretty.split(separator: "/") {
            url.appendPathComponent(String(component), isDirectory: true)
        }
        url.appendPathComponent("index.html", isDirectory: false)
        return url
    }

    /// The on-disk directory for a locale within this version (the version root
    /// for the default locale), e.g. `<output>/4.0/de/`.
    public func directory(forLocale locale: String, in outputDirectory: URL) -> URL {
        var url = outputDirectory
        for component in versionPrefix.split(separator: "/") {
            url.appendPathComponent(String(component), isDirectory: true)
        }
        if locale != defaultLocale {
            url.appendPathComponent(locale, isDirectory: true)
        }
        return url
    }

    /// The root-relative URL of a locale's search index within this version,
    /// e.g. `/4.0/de/search/search_index.json`.
    public func searchIndexURLPath(forLocale locale: String) -> String {
        basePath + "/" + versionPrefix + localePrefix(locale) + "search/search_index.json"
    }

    /// The relative path from a page back to the site root, e.g. `../../`,
    /// used to make asset links work regardless of how deep the page is.
    public func baseURL(forLogicalPath logicalPath: String, locale: String) -> String {
        // Count path segments *within the mounted site* (excluding basePath, since
        // the relative path climbs back to the mount root, wherever it's served).
        let path = versionPrefix + localePrefix(locale) + prettyPath(forLogicalPath: logicalPath)
        let depth = path.split(separator: "/").count
        return depth == 0 ? "./" : String(repeating: "../", count: depth)
    }
}
