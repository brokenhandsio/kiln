import Markdown

/// HTML escaping helpers shared by the renderer.
enum HTMLEscaping {
    /// Escape text appearing in element content.
    static func text(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(character)
            }
        }
        return result
    }

    /// Escape a value appearing inside a double-quoted attribute.
    static func attribute(_ string: String) -> String {
        text(string).replacing("\"", with: "&quot;")
    }
}

/// A `MarkupWalker` that renders a parsed markdown tree to HTML.
///
/// It extends what `swift-markdown`'s built-in `HTMLFormatter` does in two ways
/// Kiln needs: it escapes text/code content, and it adds slugged `id`s plus
/// optional permalink anchors to headings while collecting them for the table
/// of contents.
struct HTMLRenderer: MarkupWalker {
    private(set) var result = ""
    private(set) var headings: [TOCEntry] = []

    private let slugger: Slugger
    private let toc: TableOfContentsOptions

    private var inTableHead = false
    private var tableColumnAlignments: [Table.ColumnAlignment?]? = nil
    private var currentTableColumn = 0

    init(slugger: Slugger, tocOptions: TableOfContentsOptions) {
        self.slugger = slugger
        self.toc = tocOptions
    }

    // MARK: Block elements

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        result += "<blockquote>\n"
        descendInto(blockQuote)
        result += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let languageAttr: String
        if let language = codeBlock.language, !language.isEmpty {
            languageAttr = " class=\"language-\(HTMLEscaping.attribute(language))\""
        } else {
            languageAttr = ""
        }
        result += "<pre><code\(languageAttr)>\(HTMLEscaping.text(codeBlock.code))</code></pre>\n"
    }

    mutating func visitHeading(_ heading: Heading) {
        let title = heading.plainText
        let id = slugger.slug(for: title)
        headings.append(TOCEntry(level: heading.level, id: id, title: title))

        result += "<h\(heading.level) id=\"\(HTMLEscaping.attribute(id))\">"
        descendInto(heading)
        if toc.permalink {
            result += "<a class=\"headerlink\" href=\"#\(HTMLEscaping.attribute(id))\" title=\"Permanent link\">\(HTMLEscaping.text(toc.permalinkSymbol))</a>"
        }
        result += "</h\(heading.level)>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        result += "<hr />\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        result += html.rawHTML
        if !html.rawHTML.hasSuffix("\n") { result += "\n" }
    }

    mutating func visitListItem(_ listItem: ListItem) {
        result += "<li>"
        if let checkbox = listItem.checkbox {
            result += "<input type=\"checkbox\" disabled=\"\""
            if checkbox == .checked { result += " checked=\"\"" }
            result += " /> "
        }
        descendInto(listItem)
        result += "</li>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let start = orderedList.startIndex != 1 ? " start=\"\(orderedList.startIndex)\"" : ""
        result += "<ol\(start)>\n"
        descendInto(orderedList)
        result += "</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        result += "<ul>\n"
        descendInto(unorderedList)
        result += "</ul>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        result += "<p>"
        descendInto(paragraph)
        result += "</p>\n"
    }

    mutating func visitTable(_ table: Table) {
        result += "<table>\n"
        tableColumnAlignments = table.columnAlignments
        descendInto(table)
        tableColumnAlignments = nil
        result += "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        result += "<thead>\n<tr>\n"
        inTableHead = true
        currentTableColumn = 0
        descendInto(tableHead)
        inTableHead = false
        result += "</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        if !tableBody.isEmpty {
            result += "<tbody>\n"
            descendInto(tableBody)
            result += "</tbody>\n"
        }
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        result += "<tr>\n"
        currentTableColumn = 0
        descendInto(tableRow)
        result += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        guard let alignments = tableColumnAlignments, currentTableColumn < alignments.count else { return }
        guard tableCell.colspan > 0 && tableCell.rowspan > 0 else { return }

        let element = inTableHead ? "th" : "td"
        result += "<\(element)"
        if let alignment = alignments[currentTableColumn] {
            result += " align=\"\(alignment)\""
        }
        currentTableColumn += 1
        if tableCell.rowspan > 1 { result += " rowspan=\"\(tableCell.rowspan)\"" }
        if tableCell.colspan > 1 { result += " colspan=\"\(tableCell.colspan)\"" }
        result += ">"
        descendInto(tableCell)
        result += "</\(element)>\n"
    }

    // MARK: Inline elements

    private mutating func printInline(tag: String, _ content: any Markup) {
        result += "<\(tag)>"
        descendInto(content)
        result += "</\(tag)>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code>\(HTMLEscaping.text(inlineCode.code))</code>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) { printInline(tag: "em", emphasis) }
    mutating func visitStrong(_ strong: Strong) { printInline(tag: "strong", strong) }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) { printInline(tag: "del", strikethrough) }

    mutating func visitImage(_ image: Image) {
        result += "<img"
        if let source = image.source, !source.isEmpty {
            result += " src=\"\(HTMLEscaping.attribute(source))\""
        }
        let alt = image.plainText
        if !alt.isEmpty {
            result += " alt=\"\(HTMLEscaping.attribute(alt))\""
        }
        if let title = image.title, !title.isEmpty {
            result += " title=\"\(HTMLEscaping.attribute(title))\""
        }
        result += " />"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) { result += inlineHTML.rawHTML }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { result += "<br />\n" }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { result += "\n" }

    mutating func visitLink(_ link: Link) {
        result += "<a"
        if let destination = link.destination {
            result += " href=\"\(HTMLEscaping.attribute(destination))\""
        }
        result += ">"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitText(_ text: Text) {
        result += HTMLEscaping.text(text.string)
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
        if let destination = symbolLink.destination {
            result += "<code>\(HTMLEscaping.text(destination))</code>"
        }
    }
}
