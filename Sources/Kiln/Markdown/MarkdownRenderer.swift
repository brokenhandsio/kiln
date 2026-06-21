import Markdown

/// The result of rendering a markdown document.
public struct RenderedMarkdown: Sendable {
    /// The rendered HTML body.
    public var html: String
    /// The nested table of contents built from the page's headings.
    public var tableOfContents: [TOCEntry]
    /// The first level-1 heading's text, if any (used as a fallback page title).
    public var firstHeading: String?
    /// A plain-text excerpt of the first prose paragraph, truncated for use as a
    /// `<meta name="description">` when the page has no explicit description — so
    /// each page gets a unique snippet instead of the site-wide default.
    public var metaDescription: String?
    /// Raw link destinations (`<a href>`) found in the document, for link checking.
    public var links: [String]
    /// Raw image sources (`<img src>`) found in the document, for link checking.
    public var images: [String]
    /// Anchor ids of every heading on the page (for validating `#fragment` links).
    public var headingIDs: [String]
}

/// Renders markdown to HTML, applying Kiln's enabled extensions (admonitions,
/// heading anchors + table of contents) on top of `swift-markdown`.
public struct MarkdownRenderer: Sendable {
    private let options: MarkdownExtensions

    public init(options: MarkdownExtensions = MarkdownExtensions()) {
        self.options = options
    }

    public func render(_ source: String, linkResolver: LinkResolver? = nil) -> RenderedMarkdown {
        let slugger = Slugger()
        var headings: [TOCEntry] = []
        var links: [String] = []
        var images: [String] = []
        let html = renderBody(source, slugger: slugger, headings: &headings, links: &links, images: &images, linkResolver: linkResolver)
        let toc = TableOfContents.build(from: headings, levels: options.tableOfContents.levels)
        let firstHeading = headings.first(where: { $0.level == 1 })?.title
        return RenderedMarkdown(
            html: html,
            tableOfContents: toc,
            firstHeading: firstHeading,
            metaDescription: Self.metaDescription(from: source),
            links: links,
            images: images,
            headingIDs: headings.map(\.id)
        )
    }

    /// First prose paragraph as a single line of plain text, truncated to ~155
    /// characters on a word boundary (with an ellipsis) for use as a meta
    /// description. Skips headings and Kiln admonition markers.
    static func metaDescription(from source: String, maxLength: Int = 155) -> String? {
        for child in Document(parsing: source).children {
            guard let paragraph = child as? Paragraph else { continue }
            let collapsed = paragraph.plainText
                .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                .joined(separator: " ")
            if collapsed.isEmpty || collapsed.hasPrefix("!!!") { continue }
            guard collapsed.count > maxLength else { return collapsed }
            let clipped = collapsed.prefix(maxLength)
            if let lastSpace = clipped.lastIndex(of: " ") {
                return clipped[..<lastSpace] + "…"
            }
            return clipped + "…"
        }
        return nil
    }

    /// Render a (possibly nested) markdown body, sharing the slugger so anchor
    /// ids stay unique across the whole page and accumulating headings in order.
    private func renderBody(_ source: String, slugger: Slugger, headings: inout [TOCEntry], links: inout [String], images: inout [String], linkResolver: LinkResolver?) -> String {
        let segments: [MarkdownSegment] = options.admonitions
            ? AdmonitionParser.segments(from: source)
            : [.markdown(source)]

        var html = ""
        for segment in segments {
            switch segment {
            case .markdown(let text):
                guard !text.isBlank else { continue }
                let document = Document(parsing: text)
                var renderer = HTMLRenderer(slugger: slugger, tocOptions: options.tableOfContents, linkResolver: linkResolver)
                renderer.visit(document)
                html += renderer.result
                headings.append(contentsOf: renderer.headings)
                links.append(contentsOf: renderer.links)
                images.append(contentsOf: renderer.images)
            case .admonition(let admonition):
                html += renderAdmonition(admonition, slugger: slugger, headings: &headings, links: &links, images: &images, linkResolver: linkResolver)
            }
        }
        return html
    }

    private func renderAdmonition(_ admonition: Admonition, slugger: Slugger, headings: inout [TOCEntry], links: inout [String], images: inout [String], linkResolver: LinkResolver?) -> String {
        let classes = (["admonition"] + admonition.classes).joined(separator: " ")
        let bodyHTML = renderBody(admonition.body, slugger: slugger, headings: &headings, links: &links, images: &images, linkResolver: linkResolver)

        // Resolve the title: an explicit empty string suppresses it; otherwise
        // use the given title or the capitalised kind.
        let resolvedTitle: String?
        switch admonition.title {
        case .some(let title) where title.isEmpty:
            resolvedTitle = admonition.collapsible ? admonition.primaryKind.capitalizedFirstLetter : nil
        case .some(let title):
            resolvedTitle = title
        case .none:
            resolvedTitle = admonition.primaryKind.capitalizedFirstLetter
        }

        if admonition.collapsible {
            let openAttr = admonition.expanded ? " open" : ""
            var result = "<details class=\"\(HTMLEscaping.attribute(classes))\"\(openAttr)>\n"
            let title = resolvedTitle ?? admonition.primaryKind.capitalizedFirstLetter
            result += "<summary class=\"admonition-title\">\(HTMLEscaping.text(title))</summary>\n"
            result += bodyHTML
            result += "</details>\n"
            return result
        } else {
            var result = "<div class=\"\(HTMLEscaping.attribute(classes))\">\n"
            if let title = resolvedTitle {
                result += "<p class=\"admonition-title\">\(HTMLEscaping.text(title))</p>\n"
            }
            result += bodyHTML
            result += "</div>\n"
            return result
        }
    }
}
