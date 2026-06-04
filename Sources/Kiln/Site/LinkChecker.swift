/// How Kiln reacts to broken internal links found at build time.
public enum LinkChecking: Sendable {
    /// Don't check links.
    case off
    /// Print a warning for each broken link, but still finish the build (default).
    case warn
    /// Print broken links and fail the build (throw) if any are found.
    case error
}

/// A broken internal link discovered during a build.
public struct LinkIssue: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// A relative `.md` link whose target page isn't built.
        case missingPage(target: String)
        /// A `#fragment` that doesn't match any heading on the target page.
        case missingAnchor(target: String, fragment: String)
        /// A relative asset/image reference whose file doesn't exist.
        case missingAsset(path: String)
    }

    /// The content file containing the link (e.g. `"basics/routing.md"`).
    public var sourcePath: String
    /// The locale of the page the link was found on.
    public var locale: String
    /// The link/source exactly as written in the markdown.
    public var link: String
    public var kind: Kind

    /// A human-readable description of the problem.
    public var message: String {
        switch kind {
        case .missingPage(let target):
            return "links to \"\(link)\" but no page is built at \(target)"
        case .missingAnchor(let target, let fragment):
            return "links to \"\(link)\" but \(target) has no heading \"#\(fragment)\""
        case .missingAsset(let path):
            return "references \"\(link)\" but no file exists at \(path)"
        }
    }
}

/// Error thrown in ``LinkChecking/error`` mode when broken links are found.
public struct BrokenLinksError: Error, CustomStringConvertible {
    public var issues: [LinkIssue]
    public var description: String {
        "Found \(issues.count) broken link(s)."
    }
}

/// Accumulates per-page link/heading data during a build so links can be
/// validated once all pages (and their headings) are known.
final class LinkData {
    struct Record {
        var logicalPath: String
        var locale: String
        var sourcePath: String
        var links: [String]
        var images: [String]
    }

    private(set) var records: [Record] = []
    private(set) var slugs: [String: [String: Set<String>]] = [:]
    private(set) var builtPages: Set<String> = []

    func add(logicalPath: String, locale: String, sourcePath: String, rendered: RenderedMarkdown) {
        builtPages.insert(logicalPath)
        slugs[logicalPath, default: [:]][locale] = Set(rendered.headingIDs)
        records.append(Record(logicalPath: logicalPath, locale: locale, sourcePath: sourcePath,
                              links: rendered.links, images: rendered.images))
    }
}

/// Validates the internal links Kiln rewrites — relative `.md` page links,
/// `#anchor` fragments, and relative asset/image references — against the set
/// of pages actually built and the headings on each page. External/`mailto:`
/// and root-absolute links are left to other tooling.
struct LinkChecker {
    /// Logical paths that produced a built page (e.g. nav pages).
    let builtPages: Set<String>
    /// `logicalPath -> locale -> heading anchor ids` for anchor validation.
    let slugs: [String: [String: Set<String>]]
    let defaultLocale: String
    /// Locale codes recognised as filename suffixes (so `content.de.md` is
    /// treated as the logical path `content.md`).
    let knownLocales: Set<String>
    /// Whether a content-relative asset path (e.g. `images/x.png`) exists.
    let assetExists: (String) -> Bool

    func issues(forPage logicalPath: String, locale: String, sourcePath: String, links: [String], images: [String]) -> [LinkIssue] {
        var found: [LinkIssue] = []
        for link in links {
            if let issue = checkLink(link, from: logicalPath, locale: locale, sourcePath: sourcePath) {
                found.append(issue)
            }
        }
        for source in images {
            if let issue = checkAsset(source, isImage: true, from: logicalPath, locale: locale, sourcePath: sourcePath) {
                found.append(issue)
            }
        }
        return found
    }

    // MARK: Link kinds

    private func checkLink(_ raw: String, from logicalPath: String, locale: String, sourcePath: String) -> LinkIssue? {
        guard !raw.isEmpty, !isExternal(raw), !raw.hasPrefix("/") else { return nil }

        // Same-page anchor — checked against this page's own headings.
        if raw.hasPrefix("#") {
            let fragment = String(raw.dropFirst())
            guard !fragment.isEmpty else { return nil }
            if let pageSlugs = slugs[logicalPath]?[locale], !pageSlugs.contains(fragment) {
                return LinkIssue(sourcePath: sourcePath, locale: locale, link: raw,
                                 kind: .missingAnchor(target: logicalPath, fragment: fragment))
            }
            return nil
        }

        let (path, fragment) = splitFragment(raw)
        guard !path.isEmpty else { return nil }
        let resolved = LinkChecker.resolve(path, from: logicalPath)

        if resolved.hasSuffix(".md") {
            // A localised target (`content.de.md`) maps to its logical path.
            let target = LinkResolver.stripLocaleSuffix(resolved, knownLocales: knownLocales).logicalPath
            if !builtPages.contains(target) {
                return LinkIssue(sourcePath: sourcePath, locale: locale, link: raw, kind: .missingPage(target: target))
            }
            // Cross-page anchors are validated against the target's default-language
            // headings; a translated target missing the anchor is a translation gap,
            // not a broken link.
            if !fragment.isEmpty, let targetSlugs = canonicalSlugs(target), !targetSlugs.contains(fragment) {
                return LinkIssue(sourcePath: sourcePath, locale: locale, link: raw,
                                 kind: .missingAnchor(target: target, fragment: fragment))
            }
            return nil
        }

        // A relative link to a non-`.md` file is an asset reference.
        return assetExists(resolved) ? nil
            : LinkIssue(sourcePath: sourcePath, locale: locale, link: raw, kind: .missingAsset(path: resolved))
    }

    private func checkAsset(_ raw: String, isImage: Bool, from logicalPath: String, locale: String, sourcePath: String) -> LinkIssue? {
        guard !raw.isEmpty, !isExternal(raw), !raw.hasPrefix("/"), !raw.hasPrefix("data:") else { return nil }
        let (path, _) = splitFragment(stripQuery(raw))
        guard !path.isEmpty else { return nil }
        let target = LinkChecker.resolve(path, from: logicalPath)
        return assetExists(target) ? nil
            : LinkIssue(sourcePath: sourcePath, locale: locale, link: raw, kind: .missingAsset(path: target))
    }

    // MARK: Helpers

    /// Heading slugs for a page's canonical (default-language) build.
    private func canonicalSlugs(_ logicalPath: String) -> Set<String>? {
        slugs[logicalPath]?[defaultLocale] ?? slugs[logicalPath]?.first?.value
    }

    private func isExternal(_ s: String) -> Bool {
        s.hasPrefix("mailto:") || s.hasPrefix("tel:") || s.hasPrefix("//") || s.contains("://")
    }

    private func splitFragment(_ s: String) -> (path: String, fragment: String) {
        guard let hash = s.firstIndex(of: "#") else { return (s, "") }
        return (String(s[..<hash]), String(s[s.index(after: hash)...]))
    }

    private func stripQuery(_ s: String) -> String {
        guard let q = s.firstIndex(of: "?") else { return s }
        return String(s[..<q])
    }

    /// Resolve a relative path against the directory of the page it appears on,
    /// producing a content-relative logical path.
    static func resolve(_ path: String, from logicalPath: String) -> String {
        let directory: String
        if let slash = logicalPath.lastIndex(of: "/") {
            directory = String(logicalPath[..<slash])
        } else {
            directory = ""
        }
        return LinkResolver.normalise(directory + "/" + path)
    }
}
