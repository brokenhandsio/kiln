/// A documentation version (e.g. a stable release line or a pre-release).
///
/// When a ``KilnSite`` declares one or more versions, Kiln renders them all in a
/// single build: the default version at the site root (unchanged URLs), and each
/// other version under a `/<id>/` prefix. A version-picker on every page links to
/// the equivalent page in each version (falling back to that version's home when
/// the page doesn't exist there).
///
/// Versions are independent: each has its own content directory, navigation tree,
/// and set of languages, so their structure and translations can differ.
public struct DocVersion: Sendable {
    /// The version identifier used as the URL prefix and manifest key, e.g.
    /// `"4.0"`. Must be non-empty, unique, and URL-safe (no `/` or spaces).
    /// The default version uses an empty id (it lives at the root).
    public var id: String
    /// The display name shown in the version switcher, e.g. `"4.0 (latest)"`.
    public var name: String
    /// Whether this is the default version, served at the site root. Exactly one
    /// version must be the default, and it must not be a pre-release.
    public var isDefault: Bool
    /// Whether this is a pre-release (beta/RC). Pre-releases can be published but
    /// are never the default; the theme can label/group them.
    public var isPrerelease: Bool
    /// Whether this version is deprecated (used for switcher styling/labelling).
    public var deprecated: Bool
    /// Path to this version's content directory, resolved relative to the content
    /// base passed to ``Kiln/build(_:contentDirectory:outputDirectory:linkChecking:)``.
    /// Empty means "use the content base itself".
    public var contentDirectory: String
    /// This version's languages. Exactly one must have `isDefault == true`.
    public var languages: [Language]
    /// This version's navigation tree.
    public var navigation: [NavItem]
    /// This version's pages rendered outside the navigation tree — see
    /// ``UnlistedPage``.
    public var unlistedPages: [UnlistedPage]

    /// Create a documentation version.
    public init(
        id: String,
        name: String? = nil,
        isDefault: Bool = false,
        isPrerelease: Bool = false,
        deprecated: Bool = false,
        contentDirectory: String,
        languages: [Language] = [Language(.english, isDefault: true)],
        unlistedPages: [UnlistedPage] = [],
        @NavBuilder navigation: () -> [NavItem]
    ) {
        self.id = id
        self.name = name ?? id
        self.isDefault = isDefault
        self.isPrerelease = isPrerelease
        self.deprecated = deprecated
        self.contentDirectory = contentDirectory
        self.languages = languages
        self.unlistedPages = unlistedPages
        self.navigation = navigation()
    }

    /// Internal initializer taking a pre-built navigation tree (used to wrap an
    /// unversioned ``KilnSite`` as a single synthetic default version).
    init(
        id: String,
        name: String,
        isDefault: Bool,
        isPrerelease: Bool,
        deprecated: Bool,
        contentDirectory: String,
        languages: [Language],
        unlistedPages: [UnlistedPage] = [],
        navigationItems: [NavItem]
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.isPrerelease = isPrerelease
        self.deprecated = deprecated
        self.contentDirectory = contentDirectory
        self.languages = languages
        self.unlistedPages = unlistedPages
        self.navigation = navigationItems
    }

    /// The default language for this version (built at the version's root).
    public var defaultLanguage: Language {
        languages.first(where: { $0.isDefault }) ?? languages[0]
    }

    /// Languages of this version that should actually be built.
    public var buildableLanguages: [Language] {
        languages.filter { $0.build }
    }

    /// The URL/output prefix for this version: `""` for the default version
    /// (root), otherwise `"<id>/"`.
    public var urlPrefix: String {
        isDefault ? "" : id + "/"
    }
}
