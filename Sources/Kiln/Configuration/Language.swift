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
    /// Whether this language is written right-to-left. Drives the `dir="rtl"`
    /// attribute on the page shell and the direction-aware theme CSS. Defaults
    /// to the ``LanguageCode``'s direction (RTL for Arabic/Hebrew) and can be
    /// overridden for ``LanguageCode/custom(code:name:)`` locales.
    public var isRTL: Bool
    /// Optional localised site name (overrides ``KilnSite/name`` for this
    /// language), e.g. `"Vapor Dokumentation"`.
    public var siteName: String?
    /// Optional localised default meta description (overrides
    /// ``KilnSite/description`` for pages in this language without their own).
    public var description: String?
    /// Optional per-language social/OpenGraph preview image, overriding
    /// ``KilnSite/image`` for pages in this language that don't set their own
    /// `image:` front matter. Same form as ``KilnSite/image`` — a content-relative
    /// path (e.g. `"assets/social-card.de.png"`) or an absolute URL — so the
    /// social-image precedence is page front matter → this → ``KilnSite/image``.
    public var image: String?
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
    ///   - isRTL: overrides the writing direction. Defaults to the code's own
    ///     direction (RTL for Arabic/Hebrew, LTR otherwise); pass `true`/`false`
    ///     for a ``LanguageCode/custom(code:name:)`` locale Kiln can't classify.
    public init(
        _ code: LanguageCode,
        isDefault: Bool = false,
        build: Bool = true,
        name: String? = nil,
        isRTL: Bool? = nil,
        siteName: String? = nil,
        description: String? = nil,
        navTranslations: [String: String] = [:],
        customStrings: [String: String] = [:],
        // Grouped next to `localisation` so callers that pass `customStrings`
        // can append `image:`/`localisation:` in source order.
        image: String? = nil,
        localisation: LocalisationConfiguration = LocalisationConfiguration()
    ) {
        self.locale = code.code
        self.name = name ?? code.name
        self.isDefault = isDefault
        self.build = build
        self.isRTL = isRTL ?? code.isRTL
        self.siteName = siteName
        self.description = description
        self.image = image
        self.navTranslations = navTranslations
        self.customStrings = customStrings
        self.localisation = localisation
    }
}
