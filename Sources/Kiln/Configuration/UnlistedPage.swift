/// A page Kiln renders but never shows in the navigation — linked to directly
/// from a footer, another page, or an external site.
///
/// Unlisted pages get the full theme, link checking, translations and "pretty"
/// URLs like any other page. They're absent from the navigation tree, the
/// previous/next reading order, and `llms.txt` (which mirrors the nav).
///
/// ```swift
/// unlistedPages: [
///     UnlistedPage("Legal", "legal.md"),
///     UnlistedPage("Internal Notes", "notes.md", searchable: false, indexed: false),
/// ]
/// ```
public struct UnlistedPage: Sendable {
    /// A fallback title, used only when the file has neither `title:` front
    /// matter nor a first heading. (Navigation entries use their title for
    /// display; here there's nothing to display it in.)
    public var title: String
    /// The path to the markdown file, relative to the content directory, e.g.
    /// `"legal.md"`. Same logical path navigation entries use, so per-locale
    /// translations (`legal.de.md`) resolve exactly as they do for nav pages.
    public var path: String
    /// Whether the page is added to the client-side search index. Default `true`
    /// — being off the navigation isn't a reason to be unfindable on the site.
    public var searchable: Bool
    /// Whether the page is exposed to search engines: included in `sitemap.xml`
    /// and `llms-full.txt`, and rendered *without*
    /// `<meta name="robots" content="noindex">`. Default `true`.
    ///
    /// Set to `false` (usually alongside `searchable: false`) for a page that
    /// should be reachable only by direct link.
    public var indexed: Bool

    public init(_ title: String, _ path: String, searchable: Bool = true, indexed: Bool = true) {
        self.title = title
        self.path = path
        self.searchable = searchable
        self.indexed = indexed
    }
}
