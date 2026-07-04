/// Information about the source repository, used for "edit this page" links
/// and the repository link in the header.
public struct Repository: Sendable {
    /// Display name, e.g. `"Vapor GitHub"`.
    public var name: String
    /// URL of the repository, e.g. `"https://github.com/vapor/vapor"`.
    public var url: String
    /// Base URL for "edit this page" links. The page's source path is appended.
    public var editURI: String?

    public init(name: String, url: String, editURI: String? = nil) {
        self.name = name
        self.url = url
        self.editURI = editURI
    }
}

/// The complete, type-safe description of a documentation site.
///
/// This is the single source of truth a downstream docs project defines in
/// Swift; it covers everything Vapor's `mkdocs.yml` expresses today. Pass it to
/// ``Kiln/build(_:contentDirectory:outputDirectory:)`` to generate the site.
public struct KilnSite: Sendable {
    /// The site name / title.
    public var name: String
    /// The canonical site URL. When ``basePath`` is empty this is the full public
    /// URL, e.g. `"https://docs.vapor.codes/"`.
    ///
    /// - Important: When ``basePath`` is set, this must be the **scheme + host
    ///   only** (e.g. `"https://example.com"`), *not* including the subpath.
    ///   Absolute URLs (canonical, `og:url`, sitemap, `llms.txt`) are built by
    ///   joining this with the base-path-prefixed page path, so including the
    ///   subpath here too double-prefixes them
    ///   (`https://example.com/docs/docs/page/`).
    public var url: String
    /// The path the site is served under, for deployments that don't sit at the
    /// domain root (e.g. `"/docs"` for `https://example.com/docs/`). Empty by
    /// default (served from the root). Accepts `"docs"`, `"/docs"`, or `"/docs/"`
    /// — all normalised to `"/docs"`. Prefixed onto every generated root-relative
    /// link (pages, assets, theme CSS/JS, search) so they resolve in the subpath.
    ///
    /// `basePath` is a *serving* prefix, not an output directory — the build is
    /// still written at the root of the output folder and deployed *into* the
    /// subdirectory. When set, keep ``url`` to the scheme + host (see its note).
    public var basePath: String
    /// The site author.
    public var author: String?
    /// A short description used for `<meta>` tags.
    public var description: String?
    /// Default social/OpenGraph preview image (path relative to the content
    /// directory, e.g. `"assets/social-card.png"`). Pages can override it via
    /// `image:` front matter.
    public var image: String?
    /// Twitter/X handle for the `twitter:site` card tag, e.g. `"@codevapor"`.
    public var twitterSite: String?
    /// Publisher identity for JSON-LD structured data. When set, Kiln emits an
    /// `Organization` + `WebSite` graph in `<script type="application/ld+json">`
    /// (exposed to templates as `page.structuredData`).
    public var organization: Organization?
    /// Source repository information.
    public var repository: Repository?
    /// Copyright notice shown in the footer.
    public var copyright: String?
    /// Theme configuration.
    public var theme: Theme
    /// Social links shown in the footer.
    public var social: [SocialLink]
    /// Optional Carbon Ads configuration. When set, the default theme shows a
    /// Carbon ad in the table-of-contents sidebar on desktop.
    public var carbonAds: CarbonAds?
    /// Extra CSS files (relative to the content directory) to include.
    public var extraCSS: [String]
    /// Extra JavaScript files (relative to the content directory) to include.
    public var extraJavaScript: [String]
    /// Configured languages. Exactly one must have `isDefault == true`.
    public var languages: [Language]
    /// Markdown feature toggles.
    public var markdown: MarkdownExtensions
    /// Generate AI/agent-friendly output: `/llms.txt` + `/llms-full.txt` index
    /// files and a raw-markdown copy of every page (`…/index.md`) alongside its
    /// HTML, with a `<link rel="alternate" type="text/markdown">` for discovery.
    public var llmsText: Bool
    /// Whether localised pages that fall back to the default language's *content
    /// file* should still be indexable (no `robots: noindex`).
    ///
    /// By default (`false`), a localised page with no per-locale content file is
    /// treated as an untranslated fallback and marked `noindex` — it serves the
    /// default language's content at a localised URL, which would be duplicate/thin
    /// content. Set this to `true` when a site localises through `customStrings` /
    /// templates rather than per-locale content files, so its "fallback" pages are
    /// in fact fully translated and should be indexed. Does not affect the
    /// `noindex` applied to non-default documentation versions.
    public var indexFallbackPages: Bool
    /// An optional blog: a directory of dated markdown posts rendered as post
    /// pages plus generated listing pages (paginated index, per-tag pages) and
    /// an RSS feed. A site with a blog must be single-language and unversioned.
    public var blog: Blog?
    /// The navigation tree (used when the site is not versioned; otherwise each
    /// ``DocVersion`` carries its own navigation).
    public var navigation: [NavItem]
    /// Documentation versions. When non-empty, Kiln renders every version in one
    /// build: the default version at the root, others under `/<id>/`. When empty
    /// (the default), the site is unversioned and uses ``navigation``/``languages``.
    public var versions: [DocVersion]

    public init(
        name: String,
        url: String,
        basePath: String = "",
        author: String? = nil,
        description: String? = nil,
        image: String? = nil,
        twitterSite: String? = nil,
        organization: Organization? = nil,
        repository: Repository? = nil,
        copyright: String? = nil,
        theme: Theme = .default(),
        social: [SocialLink] = [],
        carbonAds: CarbonAds? = nil,
        extraCSS: [String] = [],
        extraJavaScript: [String] = [],
        languages: [Language] = [Language(.english, isDefault: true)],
        markdown: MarkdownExtensions = MarkdownExtensions(),
        llmsText: Bool = true,
        indexFallbackPages: Bool = false,
        blog: Blog? = nil,
        versions: [DocVersion] = [],
        @NavBuilder navigation: () -> [NavItem] = { [] }
    ) {
        self.name = name
        self.url = url
        self.basePath = basePath
        self.author = author
        self.description = description
        self.image = image
        self.twitterSite = twitterSite
        self.organization = organization
        self.repository = repository
        self.copyright = copyright
        self.theme = theme
        self.social = social
        self.carbonAds = carbonAds
        self.extraCSS = extraCSS
        self.extraJavaScript = extraJavaScript
        self.languages = languages
        self.markdown = markdown
        self.llmsText = llmsText
        self.indexFallbackPages = indexFallbackPages
        self.blog = blog
        self.versions = versions
        self.navigation = navigation()
    }

    /// The default language (the one built at the site root).
    public var defaultLanguage: Language {
        languages.first(where: { $0.isDefault }) ?? languages[0]
    }

    /// Languages that should actually be built.
    public var buildableLanguages: [Language] {
        languages.filter { $0.build }
    }

    /// Whether the site declares explicit documentation versions.
    public var isVersioned: Bool {
        !versions.isEmpty
    }

    /// The versions to build. For an unversioned site this is a single synthetic
    /// default version wrapping the site's `languages`/`navigation` and the
    /// content base — so the unversioned build runs the identical code path with
    /// an empty version prefix.
    public var effectiveVersions: [DocVersion] {
        if versions.isEmpty {
            return [
                DocVersion(
                    id: "",
                    name: name,
                    isDefault: true,
                    isPrerelease: false,
                    deprecated: false,
                    contentDirectory: "",
                    languages: languages,
                    navigationItems: navigation
                )
            ]
        }
        return versions
    }
}

/// Errors thrown while validating a ``KilnSite`` configuration.
public enum ConfigurationError: Error, CustomStringConvertible {
    case noLanguages
    case noDefaultLanguage
    case multipleDefaultLanguages([String])
    case noDefaultVersion
    case multipleDefaultVersions([String])
    case defaultVersionIsPrerelease(String)
    case emptyVersionID
    case invalidVersionID(String)
    case duplicateVersionID(String)
    case blogRequiresSingleUnversioned

    public var description: String {
        switch self {
        case .noLanguages:
            return "KilnSite must declare at least one language."
        case .noDefaultLanguage:
            return "KilnSite must declare exactly one default language (isDefault: true)."
        case .multipleDefaultLanguages(let locales):
            return "KilnSite declares multiple default languages: \(locales.joined(separator: ", ")). Exactly one is allowed."
        case .noDefaultVersion:
            return "KilnSite must declare exactly one default version (isDefault: true)."
        case .multipleDefaultVersions(let ids):
            return "KilnSite declares multiple default versions: \(ids.joined(separator: ", ")). Exactly one is allowed."
        case .defaultVersionIsPrerelease(let id):
            return "The default version '\(id)' must not be a pre-release."
        case .emptyVersionID:
            return "Every DocVersion must have a non-empty id."
        case .invalidVersionID(let id):
            return "Version id '\(id)' is invalid: ids must not contain '/' or whitespace."
        case .duplicateVersionID(let id):
            return "Duplicate version id '\(id)'. Version ids must be unique."
        case .blogRequiresSingleUnversioned:
            return "A KilnSite with a blog must be single-language and unversioned (one language, no versions)."
        }
    }
}

extension KilnSite {
    /// Validate invariants that can't be expressed in the type system.
    public func validate() throws {
        // A blog keeps the generated-page pipeline free of version/locale
        // prefixes, so it requires a single-language, unversioned site.
        if blog != nil, !versions.isEmpty || buildableLanguages.count != 1 {
            throw ConfigurationError.blogRequiresSingleUnversioned
        }
        if versions.isEmpty {
            try Self.validateLanguages(languages)
        } else {
            let defaults = versions.filter { $0.isDefault }
            if defaults.isEmpty { throw ConfigurationError.noDefaultVersion }
            if defaults.count > 1 {
                throw ConfigurationError.multipleDefaultVersions(defaults.map { $0.id })
            }
            if let def = defaults.first, def.isPrerelease {
                throw ConfigurationError.defaultVersionIsPrerelease(def.id)
            }
            var seen = Set<String>()
            for version in versions {
                if version.id.isEmpty { throw ConfigurationError.emptyVersionID }
                if version.id.contains("/") || version.id.contains(where: \.isWhitespace) {
                    throw ConfigurationError.invalidVersionID(version.id)
                }
                if !seen.insert(version.id).inserted {
                    throw ConfigurationError.duplicateVersionID(version.id)
                }
                try Self.validateLanguages(version.languages)
            }
        }
    }

    /// Validate the single-default-language invariant for a set of languages.
    static func validateLanguages(_ languages: [Language]) throws {
        guard !languages.isEmpty else { throw ConfigurationError.noLanguages }
        let defaults = languages.filter { $0.isDefault }
        if defaults.isEmpty { throw ConfigurationError.noDefaultLanguage }
        if defaults.count > 1 {
            throw ConfigurationError.multipleDefaultLanguages(defaults.map { $0.locale })
        }
    }
}
