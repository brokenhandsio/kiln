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

    public init(defaultLocale: String, versionPrefix: String = "") {
        self.defaultLocale = defaultLocale
        self.versionPrefix = versionPrefix
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

    /// The absolute, site-relative URL for a page, e.g. `/4.0/de/install/macos/`.
    public func urlPath(forLogicalPath logicalPath: String, locale: String) -> String {
        "/" + versionPrefix + localePrefix(locale) + prettyPath(forLogicalPath: logicalPath)
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
        "/" + versionPrefix + localePrefix(locale) + "search/search_index.json"
    }

    /// The relative path from a page back to the site root, e.g. `../../`,
    /// used to make asset links work regardless of how deep the page is.
    public func baseURL(forLogicalPath logicalPath: String, locale: String) -> String {
        let url = urlPath(forLogicalPath: logicalPath, locale: locale)
        // Count path segments (excluding the leading slash). Each becomes one
        // "../" to climb back to the root.
        let depth = url.split(separator: "/").count
        return depth == 0 ? "./" : String(repeating: "../", count: depth)
    }
}
