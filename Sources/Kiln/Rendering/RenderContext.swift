import LeafKit

/// An entry in the language switcher.
public struct LanguageAlternate: Sendable {
    public var locale: String
    public var name: String
    /// Relative URL of this page in the alternate language (e.g. `/de/`). Relative
    /// so the on-page language switcher stays portable across deploy domains
    /// (PR previews, staging) rather than hard-linking the production host.
    public var url: String
    /// Absolute URL of this page in the alternate language (e.g.
    /// `https://www.vapor.codes/de/`). Absolute so it's valid in `hreflang` links,
    /// which Google requires to be fully-qualified.
    public var absoluteURL: String
    public var isCurrent: Bool
    /// Whether this alternate is the site's default language — used to also emit
    /// an `hreflang="x-default"` link pointing at it.
    public var isDefault: Bool

    public init(locale: String, name: String, url: String, absoluteURL: String, isCurrent: Bool, isDefault: Bool = false) {
        self.locale = locale
        self.name = name
        self.url = url
        self.absoluteURL = absoluteURL
        self.isCurrent = isCurrent
        self.isDefault = isDefault
    }
}

/// An entry in the version switcher (the URL is this page's equivalent in that
/// version, or that version's home if the page doesn't exist there).
public struct VersionAlternate: Sendable {
    public var id: String
    public var name: String
    public var url: String
    public var isCurrent: Bool
    public var isPrerelease: Bool
    public var deprecated: Bool

    public init(id: String, name: String, url: String, isCurrent: Bool, isPrerelease: Bool, deprecated: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.isCurrent = isCurrent
        self.isPrerelease = isPrerelease
        self.deprecated = deprecated
    }
}

/// Per-page versioning data passed to templates. The default (neutral) value
/// produces no version-related markup, so unversioned sites are unchanged.
struct VersionContext: Sendable {
    var isVersioned: Bool = false
    var alternates: [VersionAlternate] = []
    var currentID: String = ""
    var currentName: String = ""
    var isPrerelease: Bool = false
    var deprecated: Bool = false
    /// Whether the current version is the default (latest) one.
    var isLatest: Bool = true
    /// The latest version's home URL (for the "view latest version" banner).
    var latestURL: String? = nil
    /// `""` for the default version, else `/<id>` (no trailing slash), for search.js.
    var basePath: String = ""
    /// Emit `<meta name="robots" content="noindex">` (non-default versions).
    var noindex: Bool = false
}

/// Everything a Leaf template needs to render one page, assembled into the
/// `[String: LeafData]` context `LeafRenderer` expects.
///
/// Templates reference values dotted from these top-level keys: `site`, `page`,
/// `nav`, `language`, `languages`, and `baseURL`. The page body is exposed as
/// raw HTML and should be emitted with `#unsafeHTML(page.content)`.
struct RenderContext {
    var site: KilnSite
    var language: Language
    var localisation: LocalisationConfiguration
    var alternates: [LanguageAlternate]
    var searchEnabled: Bool
    var searchIndexURL: String
    /// URL of this page's raw-markdown copy, if generated (`<page>/index.md`).
    var markdownURL: String?
    var baseURL: String

    var pageTitle: String
    var contentHTML: String
    var tableOfContents: [TOCEntry]
    var frontMatter: FrontMatter
    var pageURL: String
    /// Absolute canonical URL of this page (for `<link rel=canonical>` and `og:url`).
    var canonicalURL: String
    /// Resolved meta/OpenGraph description (page front matter or site default).
    var pageDescription: String?
    /// Absolute URL of the social/OpenGraph preview image, if any.
    var socialImageURL: String?
    var editURL: String?
    var sourcePath: String
    var isHome: Bool
    var isFallback: Bool

    var navigation: PageNavigation

    /// Versioning data (neutral by default ⇒ no version markup for unversioned sites).
    var version: VersionContext = VersionContext()

    /// The localised site name (falls back to the global site name).
    private var siteName: String {
        language.siteName ?? site.name
    }

    var leafData: [String: LeafData] {
        [
            "site": siteData,
            "language": languageData,
            "languages": .array(alternates.map(Self.alternateData)),
            "page": pageData,
            "nav": navData,
            "strings": stringsData,
            "customStrings": customStringsData,
            "baseURL": .string(baseURL),
            "searchIndexURL": .string(searchIndexURL),
            "markdownURL": .string(markdownURL),
            "versions": .array(version.alternates.map(Self.versionAlternateData)),
            "currentVersion": currentVersionData,
            "isVersioned": .bool(version.isVersioned),
            "isLatest": .bool(version.isLatest),
            "latestURL": .string(version.latestURL),
            "versionBasePath": .string(version.basePath),
            "noindex": .bool(version.noindex),
        ]
    }

    private var currentVersionData: LeafData {
        .dictionary([
            "id": .string(version.currentID),
            "name": .string(version.currentName),
            "isPrerelease": .bool(version.isPrerelease),
            "deprecated": .bool(version.deprecated),
            "isLatest": .bool(version.isLatest),
        ])
    }

    private static func versionAlternateData(_ alternate: VersionAlternate) -> LeafData {
        .dictionary([
            "id": .string(alternate.id),
            "name": .string(alternate.name),
            "url": .string(alternate.url),
            "isCurrent": .bool(alternate.isCurrent),
            "isPrerelease": .bool(alternate.isPrerelease),
            "deprecated": .bool(alternate.deprecated),
        ])
    }

    // MARK: Site

    private var siteData: LeafData {
        var dict: [String: LeafData] = [
            "name": .string(siteName),
            "globalName": .string(site.name),
            "url": .string(site.url),
            "description": .string(site.description),
            "author": .string(site.author),
            "copyright": .string(site.copyright),
            "logo": .string(site.theme.logo),
            "favicon": .string(site.theme.favicon),
            "social": .array(site.social.map(Self.socialData)),
            "extraCSS": .array(site.extraCSS.map { .string($0) }),
            "extraJS": .array(site.extraJavaScript.map { .string($0) }),
            "searchEnabled": .bool(searchEnabled),
            "twitterSite": .string(site.twitterSite),
            "palette": paletteData,
            "features": featuresData,
        ]
        if let repository = site.repository {
            dict["repository"] = .dictionary([
                "name": .string(repository.name),
                "url": .string(repository.url),
                "editURI": .string(repository.editURI),
            ])
        }
        if let fonts = site.theme.fonts {
            dict["fonts"] = .dictionary([
                "text": .string(fonts.text),
                "code": .string(fonts.code),
            ])
        }
        if let carbon = site.carbonAds {
            dict["carbonAds"] = .dictionary([
                "serve": .string(carbon.serve),
                "placement": .string(carbon.placement),
            ])
        }
        return .dictionary(dict)
    }

    private var paletteData: LeafData {
        .dictionary([
            "primary": .string(site.theme.palette.primary.css),
            "accent": .string(site.theme.palette.accent.css),
            "mode": .string(site.theme.palette.defaultMode.rawValue),
        ])
    }

    private var featuresData: LeafData {
        .dictionary([
            "searchSuggest": .bool(site.theme.features.contains(.searchSuggest)),
            "searchHighlight": .bool(site.theme.features.contains(.searchHighlight)),
            "navigationTabs": .bool(site.theme.features.contains(.navigationTabs)),
            "backToTop": .bool(site.theme.features.contains(.backToTop)),
        ])
    }

    private static func socialData(_ social: SocialLink) -> LeafData {
        .dictionary([
            "name": .string(social.icon.name),
            "link": .string(social.link),
        ])
    }

    // MARK: Language

    // MARK: Localised strings

    private var stringsData: LeafData {
        let s = localisation.resolved
        return .dictionary([
            "searchPlaceholder": .string(s.searchPlaceholder),
            "searchNoResults": .string(s.searchNoResults),
            "tableOfContentsTitle": .string(s.tableOfContentsTitle),
            "previousPage": .string(s.previousPage),
            "nextPage": .string(s.nextPage),
            "editPage": .string(s.editPage),
            "fallbackTitle": .string(s.fallbackTitle),
            "fallbackMessage": .string(s.fallbackMessage),
            "notFoundTitle": .string(s.notFoundTitle),
            "notFoundMessage": .string(s.notFoundMessage),
            "notFoundLink": .string(s.notFoundLink),
            "toggleNavigation": .string(s.toggleNavigation),
            "toggleColourScheme": .string(s.toggleColourScheme),
            "oldVersionMessage": .string(s.oldVersionMessage),
            "oldVersionLink": .string(s.oldVersionLink),
            "preReleaseMessage": .string(s.preReleaseMessage),
            "preReleaseLink": .string(s.preReleaseLink),
            "home": .string(s.home),
            "store": .string(s.store),
            "blog": .string(s.blog),
            "showcase": .string(s.showcase),
            "team": .string(s.team),
            "help": .string(s.help),
            "pressKit": .string(s.pressKit),
            "community": .string(s.community),
            "resources": .string(s.resources),
            "language": .string(s.language),
            "version": .string(s.version),
            "theme": .string(s.theme),
            "lightTheme": .string(s.lightTheme),
            "darkTheme": .string(s.darkTheme),
            "systemTheme": .string(s.systemTheme),
        ])
    }

    /// Per-language custom strings (``Language/customStrings``) for the custom
    /// `#localise("key")` tag, resolved with the default language's values as a
    /// fallback so an untranslated key still renders the default-language text.
    private var customStringsData: LeafData {
        var merged = site.defaultLanguage.customStrings
        for (key, value) in language.customStrings {
            merged[key] = value
        }
        return .dictionary(merged.mapValues { LeafData.string($0) })
    }

    private var languageData: LeafData {
        .dictionary([
            "locale": .string(language.locale),
            "name": .string(language.name),
            "isDefault": .bool(language.isDefault),
            // Path prefix for the current language: "" for the default language
            // (pages live at the site root) and "/<locale>" otherwise (pages live
            // under `/<locale>/`). Prepend it to hand-authored internal links so a
            // template like `#(language.pathPrefix)/showcase` resolves to the
            // current locale's page instead of jumping back to the default.
            "pathPrefix": .string(language.isDefault ? "" : "/" + language.locale),
            // OpenGraph locale form of the code: `language_TERRITORY` with an
            // underscore (e.g. `pt-BR` → `pt_BR`), for `<meta property="og:locale">`.
            // A bare language code (`en`) is left as-is.
            "ogLocale": .string(String(language.locale.map { $0 == "-" ? "_" : $0 })),
        ])
    }

    private static func alternateData(_ alternate: LanguageAlternate) -> LeafData {
        .dictionary([
            "locale": .string(alternate.locale),
            "name": .string(alternate.name),
            "url": .string(alternate.url),
            "absoluteURL": .string(alternate.absoluteURL),
            "isCurrent": .bool(alternate.isCurrent),
            "isDefault": .bool(alternate.isDefault),
        ])
    }

    // MARK: Page

    private var pageData: LeafData {
        var frontMatterData: [String: LeafData] = [:]
        for (key, value) in frontMatter.values {
            frontMatterData[key] = .string(value)
        }
        let toc = tableOfContents.map(Self.tocData)
        // Opt-in front-matter flags to hide the chrome rails on a per-page basis
        // (`sidebar: false` / `toc: false`). Front-matter values are stringified,
        // so an absent key leaves the rail showing — keeping every existing page
        // (and the docs site) unchanged.
        let showSidebar = frontMatter.values["sidebar"] != "false"
        let showTOC = frontMatter.values["toc"] != "false"
        return .dictionary([
            "title": .string(pageTitle),
            "content": .string(contentHTML),
            "toc": .array(toc),
            "hasTOC": .bool(!toc.isEmpty),
            "showSidebar": .bool(showSidebar),
            "showTOC": .bool(showTOC),
            "frontMatter": .dictionary(frontMatterData),
            "url": .string(pageURL),
            "canonicalURL": .string(canonicalURL),
            "description": .string(pageDescription),
            // JSON-LD structured data (Organization + WebSite); "" when no
            // organization is configured. Emit raw via `#unsafeHTML(...)`.
            "structuredData": .string(
                StructuredData.jsonLD(
                    siteName: siteName,
                    siteURL: site.url,
                    locale: language.locale,
                    organization: site.organization
                ) ?? ""
            ),
            "imageURL": .string(socialImageURL),
            "editURL": .string(editURL),
            "sourcePath": .string(sourcePath),
            "isHome": .bool(isHome),
            "isFallback": .bool(isFallback),
            "locale": .string(language.locale),
        ])
    }

    private static func tocData(_ entry: TOCEntry) -> LeafData {
        .dictionary([
            "level": .int(entry.level),
            "id": .string(entry.id),
            "title": .string(entry.title),
            "children": .array(entry.children.map(tocData)),
            "hasChildren": .bool(!entry.children.isEmpty),
        ])
    }

    // MARK: Navigation

    private var navData: LeafData {
        let nodes: LeafData = .array(navigation.nodes.map(Self.navNodeData))
        var dict: [String: LeafData] = [
            "nodes": nodes,
            // Alias so the recursive `nav-tree` partial can iterate `items`
            // uniformly whether it's given the root nav or a section node.
            "items": nodes,
        ]
        if let previous = navigation.previous {
            dict["previous"] = .dictionary(["title": .string(previous.title), "url": .string(previous.url)])
        }
        if let next = navigation.next {
            dict["next"] = .dictionary(["title": .string(next.title), "url": .string(next.url)])
        }
        return .dictionary(dict)
    }

    private static func navNodeData(_ node: NavNode) -> LeafData {
        .dictionary([
            "kind": .string(node.kind.rawValue),
            "title": .string(node.title),
            "url": .string(node.url),
            "logicalPath": .string(node.logicalPath),
            "isActive": .bool(node.isActive),
            "isCurrent": .bool(node.isCurrent),
            "items": .array(node.items.map(navNodeData)),
            "hasItems": .bool(!node.items.isEmpty),
        ])
    }
}
