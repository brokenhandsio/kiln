public import Foundation

/// Fonts used by the default theme. A `nil` value keeps the theme's built-in
/// system font stack (equivalent to MkDocs' `font: false`).
public struct Fonts: Sendable, Equatable {
    /// Font family for body text, e.g. `"Roboto Slab"`.
    public var text: String?
    /// Font family for code, e.g. `"Source Code Pro"`.
    public var code: String?

    public init(text: String? = nil, code: String? = nil) {
        self.text = text
        self.code = code
    }
}

/// Optional theme features that can be toggled on, mirroring MkDocs Material's
/// `theme.features` list.
public enum ThemeFeature: String, Sendable, Hashable {
    /// Show search suggestions as the visitor types.
    case searchSuggest = "search.suggest"
    /// Highlight search terms on the destination page.
    case searchHighlight = "search.highlight"
    /// Render top-level navigation sections as tabs.
    case navigationTabs = "navigation.tabs"
    /// Add a "back to top" button.
    case backToTop = "navigation.top"
}

/// Theme configuration.
///
/// Kiln ships a single, modern built-in theme (`.default`). Point `source` at a
/// directory of your own Leaf templates and assets with `.custom(directory:)`
/// to override any part of it — templates resolve from your directory first and
/// fall back to the bundled theme, so you only override what you need.
///
/// `sharedLayers` inserts additional theme directories *between* your custom
/// directory and the bundled default. These are typically resource-bundle
/// directories shipped by a shared design package (via `Bundle.module`), letting
/// several sites pull in one set of common templates while still overriding
/// individual templates locally. Resolution order is:
/// custom directory → shared layers (in order) → bundled default.
public struct Theme: Sendable {
    public enum Source: Sendable {
        /// Use Kiln's bundled default theme.
        case `default`
        /// Override the default theme with templates/assets from this directory
        /// (resolved relative to the package root, falling back to the bundle).
        case custom(directory: String)
    }

    public var source: Source
    /// Additional theme layers — absolute directories, typically derived from a
    /// shared design package's `Bundle.module` — inserted between the site's
    /// custom directory and Kiln's bundled default. Earlier entries win for
    /// templates; later entries' assets override earlier ones.
    public var sharedLayers: [URL]
    public var palette: Palette
    /// Path (relative to the content directory's assets) to a logo image.
    public var logo: String?
    /// Path to a favicon image.
    public var favicon: String?
    public var fonts: Fonts?
    public var features: Set<ThemeFeature>

    public init(
        source: Source = .default,
        sharedLayers: [URL] = [],
        palette: Palette = Palette(),
        logo: String? = nil,
        favicon: String? = nil,
        fonts: Fonts? = nil,
        features: Set<ThemeFeature> = [.searchSuggest, .searchHighlight]
    ) {
        self.source = source
        self.sharedLayers = sharedLayers
        self.palette = palette
        self.logo = logo
        self.favicon = favicon
        self.fonts = fonts
        self.features = features
    }

    /// Kiln's bundled default theme.
    public static func `default`(
        sharedLayers: [URL] = [],
        palette: Palette = Palette(),
        logo: String? = nil,
        favicon: String? = nil,
        fonts: Fonts? = nil,
        features: Set<ThemeFeature> = [.searchSuggest, .searchHighlight]
    ) -> Theme {
        Theme(source: .default, sharedLayers: sharedLayers, palette: palette, logo: logo, favicon: favicon, fonts: fonts, features: features)
    }

    /// A theme that overrides the bundled default with your own templates/assets.
    public static func custom(
        directory: String,
        sharedLayers: [URL] = [],
        palette: Palette = Palette(),
        logo: String? = nil,
        favicon: String? = nil,
        fonts: Fonts? = nil,
        features: Set<ThemeFeature> = [.searchSuggest, .searchHighlight]
    ) -> Theme {
        Theme(source: .custom(directory: directory), sharedLayers: sharedLayers, palette: palette, logo: logo, favicon: favicon, fonts: fonts, features: features)
    }
}
