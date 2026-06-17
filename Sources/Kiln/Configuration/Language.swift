/// A documentation language.
///
/// Content files are matched to a language by a locale suffix on the filename
/// (`index.md` for the default language, `index.de.md` for German). When a page
/// is missing a translation, Kiln falls back to the default language — the
/// equivalent of mkdocs-static-i18n's `fallback_to_default: true`.
public struct Language: Sendable {
    /// The locale code, e.g. `"en"`, `"de"`, `"zh"`.
    public var locale: String
    /// The display name shown in the language switcher, e.g. `"English"`.
    public var name: String
    /// Whether this is the default language (built at the site root). Exactly
    /// one language must be the default.
    public var isDefault: Bool
    /// Whether to build this language. Set to `false` to keep a translation in
    /// the repo without publishing it.
    public var build: Bool
    /// Optional localised site name (overrides ``KilnSite/name`` for this
    /// language), e.g. `"Vapor Dokumentation"`.
    public var siteName: String?
    /// Optional localised default meta description (overrides
    /// ``KilnSite/description`` for pages in this language without their own).
    public var description: String?
    /// Translations for navigation titles, keyed by the default-language title,
    /// e.g. `["Advanced": "Erweitert"]`.
    public var navTranslations: [String: String]
    /// Theme-defined localised strings, keyed by an arbitrary identifier, for
    /// text that isn't part of Kiln's built-in chrome (e.g. a tagline or a
    /// "Join our Discord" link). Look them up in templates with the `#localise("key")`
    /// tag. Keys missing from a non-default language fall back to the default
    /// language's value, e.g. `["tagline": "Build APIs in Swift"]`.
    public var customStrings: [String: String]
    /// Localised UI strings (search box, nav labels, error page, …) for this
    /// language. Unset strings fall back to Kiln's English defaults.
    public var localisation: LocalisationConfiguration

    /// Create a language from a ``LanguageCode``.
    ///
    /// - Parameters:
    ///   - code: the language (e.g. `.english`, `.german`, or `.custom`).
    ///   - name: overrides the code's default display name in the switcher.
    public init(
        _ code: LanguageCode,
        isDefault: Bool = false,
        build: Bool = true,
        name: String? = nil,
        siteName: String? = nil,
        description: String? = nil,
        navTranslations: [String: String] = [:],
        customStrings: [String: String] = [:],
        localisation: LocalisationConfiguration = LocalisationConfiguration()
    ) {
        self.locale = code.code
        self.name = name ?? code.name
        self.isDefault = isDefault
        self.build = build
        self.siteName = siteName
        self.description = description
        self.navTranslations = navTranslations
        self.customStrings = customStrings
        self.localisation = localisation
    }
}
