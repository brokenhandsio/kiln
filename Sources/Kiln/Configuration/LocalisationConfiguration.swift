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
        toggleColourScheme: String? = nil
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
            toggleColourScheme: toggleColourScheme ?? "Toggle colour scheme"
        )
    }
}
