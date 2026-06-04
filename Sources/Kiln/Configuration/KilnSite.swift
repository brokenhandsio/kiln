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
    /// The canonical site URL, e.g. `"https://docs.vapor.codes/"`.
    public var url: String
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
    /// The navigation tree.
    public var navigation: [NavItem]

    public init(
        name: String,
        url: String,
        author: String? = nil,
        description: String? = nil,
        image: String? = nil,
        twitterSite: String? = nil,
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
        @NavBuilder navigation: () -> [NavItem]
    ) {
        self.name = name
        self.url = url
        self.author = author
        self.description = description
        self.image = image
        self.twitterSite = twitterSite
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
}

/// Errors thrown while validating a ``KilnSite`` configuration.
public enum ConfigurationError: Error, CustomStringConvertible {
    case noLanguages
    case noDefaultLanguage
    case multipleDefaultLanguages([String])

    public var description: String {
        switch self {
        case .noLanguages:
            return "KilnSite must declare at least one language."
        case .noDefaultLanguage:
            return "KilnSite must declare exactly one default language (isDefault: true)."
        case .multipleDefaultLanguages(let locales):
            return "KilnSite declares multiple default languages: \(locales.joined(separator: ", ")). Exactly one is allowed."
        }
    }
}

extension KilnSite {
    /// Validate invariants that can't be expressed in the type system.
    public func validate() throws {
        guard !languages.isEmpty else { throw ConfigurationError.noLanguages }
        let defaults = languages.filter { $0.isDefault }
        if defaults.isEmpty { throw ConfigurationError.noDefaultLanguage }
        if defaults.count > 1 {
            throw ConfigurationError.multipleDefaultLanguages(defaults.map { $0.locale })
        }
    }
}
