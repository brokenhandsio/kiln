/// A CSS colour used to tint the default theme's palette.
///
/// Use one of the named presets (which mirror the colours available in the
/// MkDocs Material palette Vapor uses today) or supply any CSS colour string.
public struct Color: Sendable, Equatable {
    /// The raw CSS value, e.g. `"#2196f3"` or `"rebeccapurple"`.
    public var css: String

    public init(_ css: String) {
        self.css = css
    }
}

extension Color {
    public static let black = Color("#1c1c1e")
    public static let white = Color("#ffffff")
    public static let blue = Color("#2f6feb")
    public static let indigo = Color("#5e5ce6")
    public static let teal = Color("#0aa2a2")
    public static let green = Color("#2da44e")
    public static let red = Color("#cf222e")
    public static let orange = Color("#e36209")
    public static let purple = Color("#8250df")
    public static let pink = Color("#bf3989")
}
