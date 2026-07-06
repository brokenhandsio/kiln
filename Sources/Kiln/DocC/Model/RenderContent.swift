// DocC's rendered content is a tree of inline and block elements, each tagged by
// a `"type"` discriminator. Both enums below decode by that discriminator and
// fall back to `.unknown` (recording it via ``DocCDiagnostics``) for any type
// they don't model — so an additive DocC change degrades to a visible gap rather
// than a decode failure. The recursion runs through `Array`, so no `indirect`.

/// A span of inline content: text, styled runs, inline code, links, and symbol
/// references.
public enum RenderInlineContent: Sendable {
    /// Plain text.
    case text(String)
    /// Inline code (`` `code` ``).
    case codeVoice(code: String)
    /// Emphasised (italic) run.
    case emphasis([RenderInlineContent])
    /// Strong (bold) run.
    case strong([RenderInlineContent])
    /// Struck-through run.
    case strikethrough([RenderInlineContent])
    /// A reference to another page or asset, resolved via the node's reference
    /// map. `isActive` is false for a link that shouldn't be clickable;
    /// `overridingTitle*` replace the reference's own title when present.
    case reference(identifier: String, isActive: Bool, overridingTitle: String?, overridingTitleInlineContent: [RenderInlineContent]?)
    /// An inline image, resolved via the reference map by `identifier`.
    case image(identifier: String, metadata: RenderContentMetadata?)
    /// An external hyperlink with literal text.
    case link(title: String?, destination: String)
    /// A construct not modelled by Kiln (recorded in ``DocCDiagnostics``).
    case unknown(type: String)
}

extension RenderInlineContent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, text, code, inlineContent, identifier, isActive
        case overridingTitle, overridingTitleInlineContent, metadata, title, destination
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "codeVoice":
            self = .codeVoice(code: try c.decode(String.self, forKey: .code))
        case "emphasis", "newTerm", "inlineHead":
            self = .emphasis(try c.decode([RenderInlineContent].self, forKey: .inlineContent))
        case "strong":
            self = .strong(try c.decode([RenderInlineContent].self, forKey: .inlineContent))
        case "strikethrough":
            self = .strikethrough(try c.decode([RenderInlineContent].self, forKey: .inlineContent))
        case "reference":
            self = .reference(
                identifier: try c.decode(String.self, forKey: .identifier),
                isActive: try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true,
                overridingTitle: try c.decodeIfPresent(String.self, forKey: .overridingTitle),
                overridingTitleInlineContent: try c.decodeIfPresent([RenderInlineContent].self, forKey: .overridingTitleInlineContent)
            )
        case "image":
            self = .image(
                identifier: try c.decode(String.self, forKey: .identifier),
                metadata: try c.decodeIfPresent(RenderContentMetadata.self, forKey: .metadata)
            )
        case "link":
            self = .link(
                title: try c.decodeIfPresent(String.self, forKey: .title),
                destination: try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
            )
        default:
            decoder.recordUnknownDocC(type, at: "inline content")
            self = .unknown(type: type)
        }
    }
}

/// A block of content: paragraphs, headings, code listings, asides, lists,
/// tables, and term lists.
public enum RenderBlockContent: Sendable {
    /// A paragraph of inline content.
    case paragraph([RenderInlineContent])
    /// A section heading with its anchor slug.
    case heading(level: Int, text: String, anchor: String?)
    /// A fenced code block; `code` is one string per line.
    case codeListing(syntax: String?, code: [String])
    /// An aside/callout (note, tip, important, warning, experiment, …).
    case aside(style: String, name: String?, content: [RenderBlockContent])
    /// An ordered list.
    case orderedList(items: [RenderListItem], startIndex: Int?)
    /// An unordered list.
    case unorderedList(items: [RenderListItem])
    /// A table: an optional header mode plus rows of cells, each cell a block sequence.
    case table(header: String?, rows: [[[RenderBlockContent]]])
    /// A definition/term list.
    case termList(items: [RenderTermListItem])
    /// A block of reference links (a "Topics"-style grid/list within prose).
    case links(style: String?, items: [String])
    /// A thematic break — a horizontal rule (`---` in Markdown).
    case thematicBreak
    /// A construct not modelled by Kiln (recorded in ``DocCDiagnostics``).
    case unknown(type: String)
}

extension RenderBlockContent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, inlineContent, level, text, anchor, syntax, code
        case style, name, content, items, start, header, rows
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "paragraph":
            self = .paragraph(try c.decodeIfPresent([RenderInlineContent].self, forKey: .inlineContent) ?? [])
        case "heading":
            self = .heading(
                level: try c.decodeIfPresent(Int.self, forKey: .level) ?? 2,
                text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
                anchor: try c.decodeIfPresent(String.self, forKey: .anchor)
            )
        case "codeListing":
            self = .codeListing(
                syntax: try c.decodeIfPresent(String.self, forKey: .syntax),
                code: try c.decodeIfPresent([String].self, forKey: .code) ?? []
            )
        case "aside":
            self = .aside(
                style: try c.decodeIfPresent(String.self, forKey: .style) ?? "note",
                name: try c.decodeIfPresent(String.self, forKey: .name),
                content: try c.decodeIfPresent([RenderBlockContent].self, forKey: .content) ?? []
            )
        case "orderedList":
            self = .orderedList(
                items: try c.decodeIfPresent([RenderListItem].self, forKey: .items) ?? [],
                startIndex: try c.decodeIfPresent(Int.self, forKey: .start)
            )
        case "unorderedList":
            self = .unorderedList(items: try c.decodeIfPresent([RenderListItem].self, forKey: .items) ?? [])
        case "table":
            self = .table(
                header: try c.decodeIfPresent(String.self, forKey: .header),
                rows: try c.decodeIfPresent([[[RenderBlockContent]]].self, forKey: .rows) ?? []
            )
        case "termList":
            self = .termList(items: try c.decodeIfPresent([RenderTermListItem].self, forKey: .items) ?? [])
        case "links":
            self = .links(
                style: try c.decodeIfPresent(String.self, forKey: .style),
                items: try c.decodeIfPresent([String].self, forKey: .items) ?? []
            )
        case "thematicBreak":
            self = .thematicBreak
        default:
            decoder.recordUnknownDocC(type, at: "block content")
            self = .unknown(type: type)
        }
    }
}

/// An item in an ordered or unordered list: a sequence of block content.
public struct RenderListItem: Decodable, Sendable {
    public var content: [RenderBlockContent]
}

/// An entry in a term list: a term and its definition.
public struct RenderTermListItem: Decodable, Sendable {
    public var term: Term
    public var definition: Definition

    public struct Term: Decodable, Sendable {
        public var inlineContent: [RenderInlineContent]
    }
    public struct Definition: Decodable, Sendable {
        public var content: [RenderBlockContent]
    }
}

/// Optional metadata attached to a content element (e.g. an image's abstract and
/// device-frame/anchor hints). Modelled minimally; extended as needed.
public struct RenderContentMetadata: Decodable, Sendable {
    public var abstract: [RenderInlineContent]?
    public var anchor: String?
    public var title: String?
}
