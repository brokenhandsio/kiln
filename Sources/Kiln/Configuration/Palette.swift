/// Colour palette for the default theme.
///
/// Kiln ships a light and a dark scheme and lets the visitor toggle between
/// them (and an automatic mode that follows the operating system). This mirrors
/// the three-way palette toggle in Vapor's current Material setup.
public struct Palette: Sendable, Equatable {
    /// Which scheme to show before the visitor expresses a preference.
    @nonexhaustive
    public enum Mode: String, Sendable {
        /// Follow the operating system's `prefers-color-scheme`.
        case auto
        case light
        case dark
    }

    /// The primary brand colour (headers, sidebar accents).
    public var primary: Color
    /// The accent colour used for links and interactive highlights.
    public var accent: Color
    /// The scheme shown by default.
    public var defaultMode: Mode

    public init(primary: Color = .black, accent: Color = .blue, defaultMode: Mode = .auto) {
        self.primary = primary
        self.accent = accent
        self.defaultMode = defaultMode
    }

    /// A palette that follows the system preference, falling back to a toggle.
    public static func autoLightDark(primary: Color = .black, accent: Color = .blue) -> Palette {
        Palette(primary: primary, accent: accent, defaultMode: .auto)
    }
}
