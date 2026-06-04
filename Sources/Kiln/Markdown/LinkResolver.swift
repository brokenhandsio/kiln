/// Rewrites relative links and asset references in markdown to the URLs they
/// should have in the generated site — the job MkDocs does for `.md` links.
///
/// Resolution is performed relative to the **current page's directory**:
/// - A relative link to a `.md` file (optionally with an `#anchor`) becomes the
///   target page's pretty, locale-prefixed URL (e.g. `content.md` →
///   `/basics/content/`, `../advanced/sessions.md#config` →
///   `/advanced/sessions/#config`).
/// - Any other relative reference (images, downloads) becomes a root-absolute
///   path (e.g. `../images/x.png` → `/images/x.png`), since project assets are
///   copied to the site root preserving their layout.
/// - Absolute URLs, protocol-relative URLs, `mailto:`/`tel:`, root-absolute
///   paths, and pure `#anchors` are left untouched.
public struct LinkResolver: Sendable {
    let currentLogicalPath: String
    let locale: String
    let urls: SiteURLs

    public init(currentLogicalPath: String, locale: String, urls: SiteURLs) {
        self.currentLogicalPath = currentLogicalPath
        self.locale = locale
        self.urls = urls
    }

    public func resolve(_ destination: String) -> String {
        guard !destination.isEmpty else { return destination }

        // Leave anything already absolute or special alone.
        if destination.hasPrefix("#")
            || destination.hasPrefix("/")
            || destination.hasPrefix("mailto:")
            || destination.hasPrefix("tel:")
            || destination.hasPrefix("//")
            || destination.contains("://") {
            return destination
        }

        // Split off an #anchor fragment, if any.
        var path = destination
        var fragment = ""
        if let hash = path.firstIndex(of: "#") {
            fragment = String(path[hash...])
            path = String(path[..<hash])
        }
        guard !path.isEmpty else { return destination } // was just a fragment

        let resolved = Self.normalise(directory(of: currentLogicalPath) + "/" + path)

        if resolved.hasSuffix(".md") {
            return urls.urlPath(forLogicalPath: resolved, locale: locale) + fragment
        } else {
            return "/" + resolved + fragment
        }
    }

    /// The directory portion of a logical path (`"security/jwt.md"` → `"security"`,
    /// `"index.md"` → `""`).
    private func directory(of logicalPath: String) -> String {
        if let slash = logicalPath.lastIndex(of: "/") {
            return String(logicalPath[..<slash])
        }
        return ""
    }

    /// Resolve `.`/`..` segments in a `/`-separated path, collapsing attempts to
    /// climb above the root.
    static func normalise(_ path: String) -> String {
        var stack: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if !stack.isEmpty { stack.removeLast() }
            default:
                stack.append(String(component))
            }
        }
        return stack.joined(separator: "/")
    }
}
