/// Options controlling how headings are turned into a table of contents and
/// whether anchor permalinks are emitted next to them.
public struct TableOfContentsOptions: Sendable, Equatable {
    /// Emit a clickable permalink anchor next to each heading.
    public var permalink: Bool
    /// The symbol used for the permalink anchor.
    public var permalinkSymbol: String
    /// Heading levels to include in the table of contents (e.g. `2...3`).
    public var levels: ClosedRange<Int>

    public init(permalink: Bool = true, permalinkSymbol: String = "#", levels: ClosedRange<Int> = 2...3) {
        self.permalink = permalink
        self.permalinkSymbol = permalinkSymbol
        self.levels = levels
    }
}

/// Toggles for the markdown features Kiln supports, mirroring the
/// `markdown_extensions` block in `mkdocs.yml`.
public struct MarkdownExtensions: Sendable {
    /// Parse `!!! type "Title"` / `??? type "Title"` admonition blocks.
    public var admonitions: Bool
    /// Parse GFM footnotes.
    public var footnotes: Bool
    /// Parse `{: .class #id }` attribute lists (`attr_list`).
    public var attributeLists: Bool
    /// Parse a YAML front-matter block (`meta`).
    public var metadata: Bool
    /// Table-of-contents / heading anchor options (`toc`).
    public var tableOfContents: TableOfContentsOptions

    public init(
        admonitions: Bool = true,
        footnotes: Bool = true,
        attributeLists: Bool = true,
        metadata: Bool = true,
        tableOfContents: TableOfContentsOptions = TableOfContentsOptions()
    ) {
        self.admonitions = admonitions
        self.footnotes = footnotes
        self.attributeLists = attributeLists
        self.metadata = metadata
        self.tableOfContents = tableOfContents
    }
}
