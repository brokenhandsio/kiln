/// Rewrites relative links and asset references in markdown to the URLs they
/// should have in the generated site — the job MkDocs does for `.md` links.
///
/// Resolution is performed relative to the **current page's directory**:
/// - A relative link to a `.md` file (optionally with an `#anchor`) becomes the
///   target page's pretty, locale-prefixed URL (e.g. `content.md` →
///   `/basics/content/`, `../advanced/sessions.md#config` →
///   `/advanced/sessions/#config`).
/// - A link that names a localised file directly (`content.de.md`) resolves to
///   that locale's URL; the locale suffix is recognised and stripped.
/// - Any other relative reference (images, downloads) becomes a root-absolute
///   path (e.g. `../images/x.png` → `/images/x.png`), since project assets are
///   copied to the site root preserving their layout.
/// - Absolute URLs, protocol-relative URLs, `mailto:`/`tel:`, root-absolute
///   paths, and pure `#anchors` are left untouched.
public struct LinkResolver: Sendable {
    let currentLogicalPath: String
    let locale: String
    let urls: SiteURLs
    let knownLocales: Set<String>

    public init(currentLogicalPath: String, locale: String, urls: SiteURLs, knownLocales: Set<String> = []) {
        self.currentLogicalPath = currentLogicalPath
        self.locale = locale
        self.urls = urls
        self.knownLocales = knownLocales
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
            // A link may name a localised file directly (`content.de.md`); strip
            // the locale to the logical path and resolve to that locale's URL.
            let (logicalPath, explicitLocale) = Self.stripLocaleSuffix(resolved, knownLocales: knownLocales)
            return urls.urlPath(forLogicalPath: logicalPath, locale: explicitLocale ?? locale) + fragment
        } else {
            // A content asset (image, download). Project assets are copied under
            // the current version's prefix, so root-absolute references must
            // include it (empty for the default version), plus the site's base
            // path when mounted in a subdirectory.
            return urls.basePath + "/" + urls.versionPrefix + resolved + fragment
        }
    }

    /// Strip a recognised locale suffix from a `.md` path:
    /// `"basics/content.de.md"` → (`"basics/content.md"`, `"de"`), while
    /// `"basics/content.md"` and `"hello.world.md"` are returned unchanged with
    /// a `nil` locale.
    static func stripLocaleSuffix(_ path: String, knownLocales: Set<String>) -> (logicalPath: String, locale: String?) {
        let directory: String
        let filename: String
        if let slash = path.lastIndex(of: "/") {
            directory = String(path[...slash])
            filename = String(path[path.index(after: slash)...])
        } else {
            directory = ""
            filename = path
        }
        let components = filename.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 3, knownLocales.contains(components[components.count - 2]) else {
            return (path, nil)
        }
        let locale = components[components.count - 2]
        var logicalComponents = components
        logicalComponents.remove(at: logicalComponents.count - 2)
        return (directory + logicalComponents.joined(separator: "."), locale)
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
