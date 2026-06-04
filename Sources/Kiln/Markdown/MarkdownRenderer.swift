#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Markdown

/// The result of rendering a markdown document.
public struct RenderedMarkdown: Sendable {
    /// The rendered HTML body.
    public var html: String
    /// The nested table of contents built from the page's headings.
    public var tableOfContents: [TOCEntry]
    /// The first level-1 heading's text, if any (used as a fallback page title).
    public var firstHeading: String?
}

/// Renders markdown to HTML, applying Kiln's enabled extensions (admonitions,
/// heading anchors + table of contents) on top of `swift-markdown`.
public struct MarkdownRenderer: Sendable {
    private let options: MarkdownExtensions

    public init(options: MarkdownExtensions = MarkdownExtensions()) {
        self.options = options
    }

    public func render(_ source: String) -> RenderedMarkdown {
        let slugger = Slugger()
        var headings: [TOCEntry] = []
        let html = renderBody(source, slugger: slugger, headings: &headings)
        let toc = TableOfContents.build(from: headings, levels: options.tableOfContents.levels)
        let firstHeading = headings.first(where: { $0.level == 1 })?.title
        return RenderedMarkdown(html: html, tableOfContents: toc, firstHeading: firstHeading)
    }

    /// Render a (possibly nested) markdown body, sharing the slugger so anchor
    /// ids stay unique across the whole page and accumulating headings in order.
    private func renderBody(_ source: String, slugger: Slugger, headings: inout [TOCEntry]) -> String {
        let segments: [MarkdownSegment] = options.admonitions
            ? AdmonitionParser.segments(from: source)
            : [.markdown(source)]

        var html = ""
        for segment in segments {
            switch segment {
            case .markdown(let text):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let document = Document(parsing: text)
                var renderer = HTMLRenderer(slugger: slugger, tocOptions: options.tableOfContents)
                renderer.visit(document)
                html += renderer.result
                headings.append(contentsOf: renderer.headings)
            case .admonition(let admonition):
                html += renderAdmonition(admonition, slugger: slugger, headings: &headings)
            }
        }
        return html
    }

    private func renderAdmonition(_ admonition: Admonition, slugger: Slugger, headings: inout [TOCEntry]) -> String {
        let classes = (["admonition"] + admonition.classes).joined(separator: " ")
        let bodyHTML = renderBody(admonition.body, slugger: slugger, headings: &headings)

        // Resolve the title: an explicit empty string suppresses it; otherwise
        // use the given title or the capitalised kind.
        let resolvedTitle: String?
        switch admonition.title {
        case .some(let title) where title.isEmpty:
            resolvedTitle = admonition.collapsible ? admonition.primaryKind.capitalized : nil
        case .some(let title):
            resolvedTitle = title
        case .none:
            resolvedTitle = admonition.primaryKind.capitalized
        }

        if admonition.collapsible {
            let openAttr = admonition.expanded ? " open" : ""
            var result = "<details class=\"\(HTMLEscaping.attribute(classes))\"\(openAttr)>\n"
            let title = resolvedTitle ?? admonition.primaryKind.capitalized
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
