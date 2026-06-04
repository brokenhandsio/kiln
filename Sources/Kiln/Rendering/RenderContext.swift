import LeafKit

/// An entry in the language switcher.
public struct LanguageAlternate: Sendable {
    public var locale: String
    public var name: String
    public var url: String
    public var isCurrent: Bool

    public init(locale: String, name: String, url: String, isCurrent: Bool) {
        self.locale = locale
        self.name = name
        self.url = url
        self.isCurrent = isCurrent
    }
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
            "baseURL": .string(baseURL),
            "searchIndexURL": .string(searchIndexURL),
        ]
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
        ])
    }

    private var languageData: LeafData {
        .dictionary([
            "locale": .string(language.locale),
            "name": .string(language.name),
            "isDefault": .bool(language.isDefault),
        ])
    }

    private static func alternateData(_ alternate: LanguageAlternate) -> LeafData {
        .dictionary([
            "locale": .string(alternate.locale),
            "name": .string(alternate.name),
            "url": .string(alternate.url),
            "isCurrent": .bool(alternate.isCurrent),
        ])
    }

    // MARK: Page

    private var pageData: LeafData {
        var frontMatterData: [String: LeafData] = [:]
        for (key, value) in frontMatter.values {
            frontMatterData[key] = .string(value)
        }
        let toc = tableOfContents.map(Self.tocData)
        return .dictionary([
            "title": .string(pageTitle),
            "content": .string(contentHTML),
            "toc": .array(toc),
            "hasTOC": .bool(!toc.isEmpty),
            "frontMatter": .dictionary(frontMatterData),
            "url": .string(pageURL),
            "canonicalURL": .string(canonicalURL),
            "description": .string(pageDescription),
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
