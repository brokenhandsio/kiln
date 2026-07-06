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
    /// The default language of the page's version, used to seed fallbacks for
    /// `customStrings` (and the default locale/direction). In a versioned site the
    /// language configuration — including its custom strings — lives on the
    /// version, so this is the *version's* default language, which is not
    /// necessarily ``KilnSite/defaultLanguage`` (that one carries no per-version
    /// strings). Using it fixes `#localise` fallbacks on non-default languages.
    var defaultLanguage: Language
    var localisation: LocalisationConfiguration
    var alternates: [LanguageAlternate]
    var searchEnabled: Bool
    var searchIndexURL: String
    /// URL of this page's raw-markdown copy, if generated (`<page>/index.md`).
    var markdownURL: String?
    var baseURL: String
    /// The site's mount path (e.g. `/docs`), or `""` when served from the domain
    /// root. Prefixed onto hard-coded root-relative links in templates (theme
    /// assets, logo, favicon, home links).
    var basePath: String = ""

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
    /// Pre-rendered DocC sidebar HTML (arbitrary-depth symbol tree), or `nil` for
    /// non-DocC pages. Surfaced as `nav.doccHTML`; when set the theme injects it in
    /// place of the `nav-tree` partial.
    var doccSidebarHTML: String? = nil
    /// Pre-rendered module-switcher HTML (all hosted DocC modules, grouped), or
    /// `nil` on non-DocC pages. Surfaced as `nav.moduleSwitcher`; the theme injects
    /// it into the sidebar.
    var doccModuleSwitcherHTML: String? = nil
    /// Pre-rendered per-package version-switcher HTML, or `nil` (single-version
    /// package or non-DocC page). Surfaced as `nav.versionSwitcher`.
    var doccVersionSwitcherHTML: String? = nil

    /// Versioning data (neutral by default ⇒ no version markup for unversioned sites).
    var version: VersionContext = VersionContext()

    /// Pre-built `blogPost.*` template data for a single post page, or `nil` for
    /// non-blog pages (see ``BlogLeafData``). Emitted as `.trueNil` when absent so
    /// `#if(blogPost)` is false on every existing page.
    var blogPost: LeafData? = nil
    /// Pre-built `blogListing.*` template data for a blog index / tag page, or
    /// `nil` otherwise.
    var blogListing: LeafData? = nil
    /// Article entity for the page's JSON-LD (a blog post), or `nil` for non-post
    /// pages — adds a `BlogPosting` node to the structured-data graph.
    var articleStructuredData: ArticleStructuredData? = nil
    /// An explicit breadcrumb trail (used by blog posts, which aren't in the
    /// navigation tree so have no nav-derived breadcrumb). When set, it supplies
    /// the `BreadcrumbList` structured data.
    var breadcrumbOverride: [BreadcrumbItem]? = nil
    /// Author profile for an author page's JSON-LD — adds a `ProfilePage` +
    /// `Person` to the structured-data graph.
    var profileStructuredData: ProfileStructuredData? = nil

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
            "basePath": .string(basePath),
            "searchIndexURL": .string(searchIndexURL),
            "markdownURL": .string(markdownURL),
            "versions": .array(version.alternates.map(Self.versionAlternateData)),
            "currentVersion": currentVersionData,
            "isVersioned": .bool(version.isVersioned),
            "isLatest": .bool(version.isLatest),
            "latestURL": .string(version.latestURL),
            "versionBasePath": .string(version.basePath),
            // noindex non-default versions AND untranslated fallback pages (a
            // fallback serves the default language's content at a localised URL,
            // so indexing it would be duplicate/thin content — hreflang + the
            // canonical already point search engines at the real page). Sites that
            // localise via customStrings/templates (so their "fallbacks" are in
            // fact translated) can opt fallbacks back into indexing via
            // `KilnSite.indexFallbackPages`. Non-default versions stay noindex.
            "noindex": .bool(version.noindex || (isFallback && !site.indexFallbackPages)),
            // Blog data (post page / listing page); `.trueNil` ⇒ `#if(blogPost)`
            // and `#if(blogListing)` are false on every non-blog page.
            "blogPost": blogPost ?? .trueNil,
            "blogListing": blogListing ?? .trueNil,
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
            // The default language's locale/direction, so templates can tag
            // fallback (untranslated) content with the original language and
            // direction — e.g. English content served LTR inside an RTL page.
            "defaultLocale": .string(defaultLanguage.locale),
            "defaultDir": .string(defaultLanguage.isRTL ? "rtl" : "ltr"),
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
            "skipToContent": .string(s.skipToContent),
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
        var merged = defaultLanguage.customStrings
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
            // Writing direction for the `<html dir="…">` attribute and any
            // direction-conditional template logic.
            "direction": .string(language.isRTL ? "rtl" : "ltr"),
            "isRTL": .bool(language.isRTL),
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
            // OpenGraph form (`pt-BR` → `pt_BR`) for `og:locale:alternate`.
            "ogLocale": .string(String(alternate.locale.map { $0 == "-" ? "_" : $0 })),
        ])
    }

    // MARK: Page

    /// The breadcrumb trail for the current page: the active nav nodes from the
    /// top-level section down to (and including) the current page. Empty on the
    /// home page or when there's no navigation tree (e.g. a flat marketing site).
    private var breadcrumbItems: [BreadcrumbItem] {
        guard !isHome else { return [] }
        var items: [BreadcrumbItem] = []
        var level = navigation.nodes
        while let active = level.first(where: { $0.isActive }) {
            items.append(BreadcrumbItem(name: active.title, url: active.url))
            if active.isCurrent { break }
            level = active.items
        }
        return items
    }

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
            // Character count of the title, so templates can SERP-aware trim a
            // brand suffix on already-long titles (e.g. `#if(page.titleLength > 50)`).
            "titleLength": .int(pageTitle.count),
            "content": .string(contentHTML),
            "toc": .array(toc),
            "hasTOC": .bool(!toc.isEmpty),
            "showSidebar": .bool(showSidebar),
            "showTOC": .bool(showTOC),
            "frontMatter": .dictionary(frontMatterData),
            "url": .string(pageURL),
            "canonicalURL": .string(canonicalURL),
            "description": .string(pageDescription),
            // JSON-LD structured data (Organization / WebSite / BreadcrumbList).
            // Nil (not "") when there's nothing to emit, so `#if(page.structuredData)`
            // is false — LeafKit treats an empty string as truthy. Emit raw via
            // `#unsafeHTML(...)`.
            "structuredData": StructuredData.jsonLD(
                siteName: siteName,
                siteURL: site.url,
                locale: language.locale,
                organization: site.organization,
                breadcrumb: breadcrumbOverride ?? breadcrumbItems,
                article: articleStructuredData,
                profile: profileStructuredData
            ).map(LeafData.string) ?? .trueNil,
            // The visible breadcrumb trail — populated only when a page supplies an
            // explicit `breadcrumbOverride` (DocC symbol pages, blog posts), so
            // nav-driven pages are unchanged (`.trueNil` ⇒ `#if(page.breadcrumb)`
            // false). Each crumb: `name`, and `url` (`.trueNil` for the current,
            // unlinked page). The nav-derived trail still feeds JSON-LD above.
            "breadcrumb": breadcrumbOverride.map { crumbs in
                LeafData.array(crumbs.map { crumb in
                    LeafData.dictionary([
                        "name": .string(crumb.name),
                        "url": crumb.url.map(LeafData.string) ?? .trueNil,
                    ])
                })
            } ?? .trueNil,
            "imageURL": .string(socialImageURL),
            // MIME type of the social image (from its extension), for
            // `<meta property="og:image:type">`. Nil when unknown/imageless.
            "imageType": .string(Self.imageMIMEType(socialImageURL)),
            "editURL": .string(editURL),
            "sourcePath": .string(sourcePath),
            "isHome": .bool(isHome),
            "isFallback": .bool(isFallback),
            "locale": .string(language.locale),
        ])
    }

    /// The OpenGraph image MIME type inferred from a URL's file extension, or
    /// `nil` if there's no image or the extension isn't a known image type.
    private static func imageMIMEType(_ url: String?) -> String? {
        guard let url else { return nil }
        // Strip any query/fragment before reading the extension.
        let path = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
        let ext = (path.split(separator: ".").last.map(String.init) ?? "").lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "avif": return "image/avif"
        default: return nil
        }
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
            // Pre-rendered DocC sidebar (`.trueNil` ⇒ `#if(nav.doccHTML)` false on
            // every non-DocC page, so the standard nav-tree renders instead).
            "doccHTML": doccSidebarHTML.map(LeafData.string) ?? .trueNil,
            // Pre-rendered DocC module + version switchers (`.trueNil` off DocC).
            "moduleSwitcher": doccModuleSwitcherHTML.map(LeafData.string) ?? .trueNil,
            "versionSwitcher": doccVersionSwitcherHTML.map(LeafData.string) ?? .trueNil,
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
