/// Localised UI strings for the theme chrome (search box, navigation labels,
/// error page, …). Attach one to each ``Language`` so the interface reads in
/// that language; any string left `nil` falls back to Kiln's built-in English
/// default.
///
/// ```swift
/// Language(.german, localisation: .init(
///     searchPlaceholder: "Suchen",
///     searchNoResults: "Keine Ergebnisse gefunden",
///     tableOfContentsTitle: "Auf dieser Seite"
/// ))
/// ```
public struct LocalisationConfiguration: Sendable {
    /// Placeholder (and accessible label) for the search box. Default: `"Search"`.
    public var searchPlaceholder: String?
    /// Shown when a search returns nothing. Default: `"No results found"`.
    public var searchNoResults: String?
    /// Heading above the on-page table of contents. Default: `"On this page"`.
    public var tableOfContentsTitle: String?
    /// Label on the "previous page" link. Default: `"Previous"`.
    public var previousPage: String?
    /// Label on the "next page" link. Default: `"Next"`.
    public var nextPage: String?
    /// "Edit this page" link text. Default: `"Edit this page"`.
    public var editPage: String?
    /// Title of the fallback banner shown on untranslated pages.
    /// Default: `"Translation unavailable"`.
    public var fallbackTitle: String?
    /// Body of the fallback banner. Default: `"This page hasn't been translated
    /// yet, so the default language is shown."`.
    public var fallbackMessage: String?
    /// `<title>`/heading for the 404 page. Default: `"Page not found"`.
    public var notFoundTitle: String?
    /// Body text for the 404 page. Default: explains the page may have moved.
    public var notFoundMessage: String?
    /// "Return to the home page" link text on the 404 page.
    public var notFoundLink: String?
    /// Accessible label for the mobile navigation toggle. Default: `"Toggle navigation"`.
    public var toggleNavigation: String?
    /// Accessible label for the colour-scheme toggle. Default: `"Toggle colour scheme"`.
    public var toggleColourScheme: String?
    /// "Skip to content" link for keyboard/AT users. Default: `"Skip to content"`.
    public var skipToContent: String?
    /// Banner shown on pages that aren't the latest version. Default:
    /// `"You're viewing documentation for an older version."`.
    public var oldVersionMessage: String?
    /// Link text on the older-version banner. Default: `"View the latest version"`.
    public var oldVersionLink: String?
    /// Banner shown on pre-release versions. Default:
    /// `"You're viewing documentation for a pre-release version."`.
    public var preReleaseMessage: String?
    /// Link text on the pre-release banner. Default: `"View the latest stable version"`.
    public var preReleaseLink: String?

    // MARK: Navigation & footer chrome
    //
    // Common labels a custom theme can use for marketing-style navigation and
    // footers. Kiln's bundled theme doesn't render these, so they're optional;
    // each defaults to its English text when unset.

    /// "Home" navigation link. Default: `"Home"`.
    public var home: String?
    /// "Store" navigation link. Default: `"Store"`.
    public var store: String?
    /// "Blog" navigation link. Default: `"Blog"`.
    public var blog: String?
    /// "Showcase" navigation link. Default: `"Showcase"`.
    public var showcase: String?
    /// "Team" navigation link. Default: `"Team"`.
    public var team: String?
    /// "Help" navigation/footer link. Default: `"Help"`.
    public var help: String?
    /// "Press Kit" footer link. Default: `"Press Kit"`.
    public var pressKit: String?
    /// "Community" footer-section heading. Default: `"Community"`.
    public var community: String?
    /// "Resources" footer-section heading. Default: `"Resources"`.
    public var resources: String?
    /// Accessible label for the language picker. Default: `"Language"`.
    public var language: String?
    /// Accessible label for the version picker. Default: `"Version"`.
    public var version: String?
    /// Accessible label for the theme picker. Default: `"Theme"`.
    public var theme: String?
    /// Light colour-scheme option. Default: `"Light"`.
    public var lightTheme: String?
    /// Dark colour-scheme option. Default: `"Dark"`.
    public var darkTheme: String?
    /// System colour-scheme option. Default: `"System"`.
    public var systemTheme: String?

    public init(
        searchPlaceholder: String? = nil,
        searchNoResults: String? = nil,
        tableOfContentsTitle: String? = nil,
        previousPage: String? = nil,
        nextPage: String? = nil,
        editPage: String? = nil,
        fallbackTitle: String? = nil,
        fallbackMessage: String? = nil,
        notFoundTitle: String? = nil,
        notFoundMessage: String? = nil,
        notFoundLink: String? = nil,
        toggleNavigation: String? = nil,
        toggleColourScheme: String? = nil,
        skipToContent: String? = nil,
        oldVersionMessage: String? = nil,
        oldVersionLink: String? = nil,
        preReleaseMessage: String? = nil,
        preReleaseLink: String? = nil,
        home: String? = nil,
        store: String? = nil,
        blog: String? = nil,
        showcase: String? = nil,
        team: String? = nil,
        help: String? = nil,
        pressKit: String? = nil,
        community: String? = nil,
        resources: String? = nil,
        language: String? = nil,
        version: String? = nil,
        theme: String? = nil,
        lightTheme: String? = nil,
        darkTheme: String? = nil,
        systemTheme: String? = nil
    ) {
        self.searchPlaceholder = searchPlaceholder
        self.searchNoResults = searchNoResults
        self.tableOfContentsTitle = tableOfContentsTitle
        self.previousPage = previousPage
        self.nextPage = nextPage
        self.editPage = editPage
        self.fallbackTitle = fallbackTitle
        self.fallbackMessage = fallbackMessage
        self.notFoundTitle = notFoundTitle
        self.notFoundMessage = notFoundMessage
        self.notFoundLink = notFoundLink
        self.toggleNavigation = toggleNavigation
        self.toggleColourScheme = toggleColourScheme
        self.skipToContent = skipToContent
        self.oldVersionMessage = oldVersionMessage
        self.oldVersionLink = oldVersionLink
        self.preReleaseMessage = preReleaseMessage
        self.preReleaseLink = preReleaseLink
        self.home = home
        self.store = store
        self.blog = blog
        self.showcase = showcase
        self.team = team
        self.help = help
        self.pressKit = pressKit
        self.community = community
        self.resources = resources
        self.language = language
        self.version = version
        self.theme = theme
        self.lightTheme = lightTheme
        self.darkTheme = darkTheme
        self.systemTheme = systemTheme
    }
}

extension LocalisationConfiguration {
    /// Every UI string resolved to a concrete value (provided override or the
    /// built-in English default).
    struct Resolved: Sendable {
        var searchPlaceholder: String
        var searchNoResults: String
        var tableOfContentsTitle: String
        var previousPage: String
        var nextPage: String
        var editPage: String
        var fallbackTitle: String
        var fallbackMessage: String
        var notFoundTitle: String
        var notFoundMessage: String
        var notFoundLink: String
        var toggleNavigation: String
        var toggleColourScheme: String
        var skipToContent: String
        var oldVersionMessage: String
        var oldVersionLink: String
        var preReleaseMessage: String
        var preReleaseLink: String
        var home: String
        var store: String
        var blog: String
        var showcase: String
        var team: String
        var help: String
        var pressKit: String
        var community: String
        var resources: String
        var language: String
        var version: String
        var theme: String
        var lightTheme: String
        var darkTheme: String
        var systemTheme: String
    }

    var resolved: Resolved {
        Resolved(
            searchPlaceholder: searchPlaceholder ?? "Search",
            searchNoResults: searchNoResults ?? "No results found",
            tableOfContentsTitle: tableOfContentsTitle ?? "On this page",
            previousPage: previousPage ?? "Previous",
            nextPage: nextPage ?? "Next",
            editPage: editPage ?? "Edit this page",
            fallbackTitle: fallbackTitle ?? "Translation unavailable",
            fallbackMessage: fallbackMessage ?? "This page hasn't been translated yet, so the default language is shown.",
            notFoundTitle: notFoundTitle ?? "Page not found",
            notFoundMessage: notFoundMessage ?? "The page you are looking for may have been moved, renamed, or might never have existed.",
            notFoundLink: notFoundLink ?? "Return to the home page",
            toggleNavigation: toggleNavigation ?? "Toggle navigation",
            toggleColourScheme: toggleColourScheme ?? "Toggle colour scheme",
            skipToContent: skipToContent ?? "Skip to content",
            oldVersionMessage: oldVersionMessage ?? "You're viewing documentation for an older version.",
            oldVersionLink: oldVersionLink ?? "View the latest version",
            preReleaseMessage: preReleaseMessage ?? "You're viewing documentation for a pre-release version.",
            preReleaseLink: preReleaseLink ?? "View the latest stable version",
            home: home ?? "Home",
            store: store ?? "Store",
            blog: blog ?? "Blog",
            showcase: showcase ?? "Showcase",
            team: team ?? "Team",
            help: help ?? "Help",
            pressKit: pressKit ?? "Press Kit",
            community: community ?? "Community",
            resources: resources ?? "Resources",
            language: language ?? "Language",
            version: version ?? "Version",
            theme: theme ?? "Theme",
            lightTheme: lightTheme ?? "Light",
            darkTheme: darkTheme ?? "Dark",
            systemTheme: systemTheme ?? "System"
        )
    }
}
