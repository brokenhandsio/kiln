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
    /// Translations for navigation titles, keyed by the default-language title,
    /// e.g. `["Advanced": "Erweitert"]`.
    public var navTranslations: [String: String]

    public init(
        locale: String,
        name: String,
        isDefault: Bool = false,
        build: Bool = true,
        siteName: String? = nil,
        navTranslations: [String: String] = [:]
    ) {
        self.locale = locale
        self.name = name
        self.isDefault = isDefault
        self.build = build
        self.siteName = siteName
        self.navTranslations = navTranslations
    }
}
