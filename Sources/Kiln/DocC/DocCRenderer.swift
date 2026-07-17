/// The result of rendering a DocC ``RenderNode`` to HTML — the analogue of
/// ``RenderedMarkdown`` for API-reference pages.
public struct RenderedDocC: Sendable {
    /// The page title (the symbol/article name), e.g. `"dispatch(_:_:…)"`.
    public var title: String
    /// A human role label shown as an eyebrow, e.g. `"Instance Method"`.
    public var roleHeading: String?
    /// The symbol kind, e.g. `"method"`, `"struct"` (drives icons/labels).
    public var symbolKind: String?
    /// The abstract as plain text, for `<meta>` description and the search index.
    public var abstractText: String?
    /// The rendered page body (abstract, declaration, parameters, discussion).
    public var contentHTML: String
    /// The nested on-page table of contents built from the discussion headings
    /// and generated section headings.
    public var tableOfContents: [TOCEntry]
    /// The breadcrumb ancestry (module → … → parent), each resolved to its site
    /// URL. Excludes the current page and the site home; empty for a module
    /// landing (no ancestors). Feeds the visible trail and `BreadcrumbList` JSON-LD.
    public var breadcrumb: [BreadcrumbItem]
}

/// Renders a decoded DocC ``RenderNode`` into themed HTML for a Kiln page.
///
/// This handles the core of a symbol/article page: the abstract, the declaration
/// (with type references linked), documented parameters, and the discussion
/// prose (all inline and block content). Curated Topics, Relationships, and See
/// Also groups are layered on separately.
///
/// Links are resolved through a ``DocCLinkResolver`` built from each node's own
/// reference map; ``pathMapper`` turns archive-relative DocC URLs into site URLs
/// (identity by default).
public struct DocCRenderer: Sendable {
    private let pathMapper: @Sendable (String) -> String

    public init(pathMapper: @escaping @Sendable (String) -> String = { $0 }) {
        self.pathMapper = pathMapper
    }

    public func render(_ node: RenderNode) -> RenderedDocC {
        let resolver = DocCLinkResolver(references: node.references ?? [:], mapPath: pathMapper)
        let slugger = Slugger()
        var body = ""
        var toc: [TOCEntry] = []

        // Abstract — the lead summary under the title.
        var abstractText: String?
        if let abstract = node.abstract, !abstract.isEmpty {
            body += "<div class=\"docc-abstract\">\(DocCInline.render(abstract, resolver: resolver))</div>\n"
            abstractText = DocCInline.plainText(abstract)
        }

        // Primary content, in DocC's own order (declaration → parameters →
        // discussion for a method; declaration → discussion for a type).
        for section in node.primaryContentSections ?? [] {
            switch section {
            case .declarations(let declarations):
                body += renderDeclarations(declarations, resolver: resolver)
            case .parameters(let parameters):
                body += renderParameters(parameters, resolver: resolver, slugger: slugger, toc: &toc)
            case .content(let blocks):
                var block = DocCBlockRenderer(resolver: resolver, slugger: slugger)
                block.render(blocks)
                body += block.html
                toc += block.headings
            case .possibleValues(let values):
                body += renderPossibleValues(values, resolver: resolver, slugger: slugger, toc: &toc)
            case .mentions(let identifiers):
                body += renderMentions(identifiers, resolver: resolver)
            case .unknown:
                break // recorded at decode time; nothing to render
            }
        }

        // Curated groups after the primary content, in DocC's order: Topics,
        // Default Implementations, Relationships, See Also.
        body += renderTopicGroups(node.topicSections ?? [], title: "Topics", id: "topics",
                                  cssClass: "docc-topics", resolver: resolver, slugger: slugger, toc: &toc)
        body += renderTopicGroups(node.defaultImplementationsSections ?? [], title: "Default Implementations",
                                  id: "default-implementations", cssClass: "docc-default-implementations",
                                  resolver: resolver, slugger: slugger, toc: &toc)
        body += renderRelationships(node.relationshipsSections ?? [], resolver: resolver, slugger: slugger, toc: &toc)
        body += renderTopicGroups(node.seeAlsoSections ?? [], title: "See Also", id: "see-also",
                                  cssClass: "docc-see-also", resolver: resolver, slugger: slugger, toc: &toc)

        return RenderedDocC(
            title: node.metadata.title ?? "",
            roleHeading: node.metadata.roleHeading,
            symbolKind: node.metadata.symbolKind,
            abstractText: abstractText,
            contentHTML: body,
            tableOfContents: TableOfContents.build(from: toc, levels: 1...6),
            breadcrumb: breadcrumbAncestry(node, resolver: resolver)
        )
    }

    /// The ancestor breadcrumb trail from `hierarchy.paths` (DocC's first path is
    /// the primary ancestry, module root → parent). Each identifier is resolved to
    /// a linked crumb; identifiers that resolve to no topic/URL (e.g. the bundle
    /// technology root) are skipped, and one with only a title becomes an unlinked
    /// crumb.
    private func breadcrumbAncestry(_ node: RenderNode, resolver: DocCLinkResolver) -> [BreadcrumbItem] {
        guard let path = node.hierarchy?.paths?.first else { return [] }
        var crumbs: [BreadcrumbItem] = []
        for identifier in path {
            if let link = resolver.resolveTopic(identifier) {
                crumbs.append(BreadcrumbItem(name: link.title, url: link.href))
            } else if let title = resolver.title(for: identifier) {
                crumbs.append(BreadcrumbItem(name: title, url: nil))
            }
        }
        return crumbs
    }

    // MARK: Declarations

    private func renderDeclarations(_ declarations: [RenderPrimarySection.Declaration], resolver: DocCLinkResolver) -> String {
        guard !declarations.isEmpty else { return "" }
        var out = "<div class=\"docc-declaration\">\n"
        for declaration in declarations {
            out += "<pre class=\"declaration\"><code>"
            for token in declaration.tokens {
                out += Self.renderToken(token, resolver: resolver)
            }
            out += "</code></pre>\n"
        }
        out += "</div>\n"
        return out
    }

    /// One declaration token: a `<span>` classed by token kind, wrapped in an
    /// `<a>` when it references another documented symbol.
    static func renderToken(_ token: DeclarationFragment, resolver: DocCLinkResolver) -> String {
        let text = HTMLEscaping.text(token.text)
        let cssClass = "token-\(token.kind)"
        if let identifier = token.identifier, let link = resolver.resolveTopic(identifier) {
            return "<a class=\"\(cssClass)\" href=\"\(HTMLEscaping.attribute(link.href))\">\(text)</a>"
        }
        return "<span class=\"\(cssClass)\">\(text)</span>"
    }

    // MARK: Parameters

    private func renderParameters(
        _ parameters: [RenderPrimarySection.ParameterDoc],
        resolver: DocCLinkResolver,
        slugger: Slugger,
        toc: inout [TOCEntry]
    ) -> String {
        guard !parameters.isEmpty else { return "" }
        toc.append(TOCEntry(level: 2, id: "parameters", title: "Parameters"))
        var out = "<section class=\"docc-parameters\">\n<h2 id=\"parameters\">Parameters</h2>\n<dl class=\"docc-parameter-list\">\n"
        for parameter in parameters {
            out += "<dt class=\"docc-parameter-name\"><code>\(HTMLEscaping.text(parameter.name))</code></dt>\n"
            // Parameter prose is usually a single paragraph; its (rare) headings
            // are deliberately kept out of the page TOC.
            var block = DocCBlockRenderer(resolver: resolver, slugger: slugger)
            block.render(parameter.content)
            out += "<dd class=\"docc-parameter-description\">\(block.html)</dd>\n"
        }
        out += "</dl>\n</section>\n"
        return out
    }

    // MARK: Possible values

    private func renderPossibleValues(
        _ values: [RenderPrimarySection.PossibleValue],
        resolver: DocCLinkResolver,
        slugger: Slugger,
        toc: inout [TOCEntry]
    ) -> String {
        guard !values.isEmpty else { return "" }
        toc.append(TOCEntry(level: 2, id: "possible-values", title: "Possible Values"))
        var out = "<section class=\"docc-possible-values\">\n<h2 id=\"possible-values\">Possible Values</h2>\n<dl class=\"docc-parameter-list\">\n"
        for value in values {
            out += "<dt class=\"docc-parameter-name\"><code>\(HTMLEscaping.text(value.name))</code></dt>\n"
            var block = DocCBlockRenderer(resolver: resolver, slugger: slugger)
            block.render(value.content ?? [])
            out += "<dd class=\"docc-parameter-description\">\(block.html)</dd>\n"
        }
        out += "</dl>\n</section>\n"
        return out
    }

    /// Render the "Mentioned in" section — links to articles that reference this
    /// symbol. Unresolvable identifiers are skipped; nothing is emitted if none
    /// resolve.
    private func renderMentions(_ identifiers: [String], resolver: DocCLinkResolver) -> String {
        let links = identifiers.compactMap { resolver.resolveTopic($0) }
        guard !links.isEmpty else { return "" }
        var out = "<section class=\"docc-mentions\">\n<h2 class=\"docc-mentions-title\">Mentioned in</h2>\n<ul>\n"
        for link in links {
            out += "<li><a href=\"\(HTMLEscaping.attribute(link.href))\">\(HTMLEscaping.text(link.title))</a></li>\n"
        }
        out += "</ul>\n</section>\n"
        return out
    }

    // MARK: Topics / Default Implementations / See Also

    /// Render a set of curated ``TopicGroup``s (Topics, Default Implementations,
    /// or See Also) as heading + symbol-card lists. The section heading and each
    /// named group heading are added to the page TOC.
    private func renderTopicGroups(
        _ groups: [TopicGroup],
        title: String,
        id: String,
        cssClass: String,
        resolver: DocCLinkResolver,
        slugger: Slugger,
        toc: inout [TOCEntry]
    ) -> String {
        let populated = groups.filter { !$0.identifiers.isEmpty }
        guard !populated.isEmpty else { return "" }

        toc.append(TOCEntry(level: 2, id: id, title: title))
        var out = "<section class=\"\(cssClass)\">\n<h2 id=\"\(HTMLEscaping.attribute(id))\">\(HTMLEscaping.text(title))</h2>\n"
        for group in populated {
            if let groupTitle = group.title {
                let groupID = group.anchor ?? slugger.slug(for: groupTitle)
                toc.append(TOCEntry(level: 3, id: groupID, title: groupTitle))
                out += "<h3 id=\"\(HTMLEscaping.attribute(groupID))\">\(HTMLEscaping.text(groupTitle))</h3>\n"
            }
            out += "<ul class=\"docc-topic-list\">\n"
            for identifier in group.identifiers {
                out += renderTopicCard(identifier, resolver: resolver)
            }
            out += "</ul>\n"
        }
        out += "</section>\n"
        return out
    }

    /// One curated symbol card: the linked title (inline code for a symbol) plus
    /// its abstract. Non-topic references are skipped.
    private func renderTopicCard(_ identifier: String, resolver: DocCLinkResolver) -> String {
        guard case .topic(let topic)? = resolver.reference(identifier) else { return "" }

        // A symbol card shows its abbreviated declaration fragments (kind + name +
        // types, e.g. `var subquery: SQLUnionSubquery`) like Xcode/DocC, so the
        // reader sees func/var and the return/property types at a glance. The
        // fragments render as unlinked token spans — the whole card is already a
        // link, so per-token <a>s would nest. Falls back to the plain title.
        let titleHTML: String
        if topic.kind == "symbol", let fragments = topic.fragments, !fragments.isEmpty {
            let tokens = fragments.map {
                "<span class=\"token-\($0.kind)\">\(HTMLEscaping.text($0.text))</span>"
            }.joined()
            titleHTML = "<code>\(tokens)</code>"
        } else {
            let titleText = HTMLEscaping.text(topic.title ?? identifier)
            titleHTML = topic.kind == "symbol" ? "<code>\(titleText)</code>" : titleText
        }

        let link: String
        if let url = topic.url {
            link = "<a class=\"docc-topic-link\" href=\"\(HTMLEscaping.attribute(resolver.mapPath(url)))\">\(titleHTML)</a>"
        } else {
            link = "<span class=\"docc-topic-link\">\(titleHTML)</span>"
        }

        var card = "<li class=\"docc-topic\">\(link)"
        if let abstract = topic.abstract, !abstract.isEmpty {
            card += "<div class=\"docc-topic-abstract\">\(DocCInline.render(abstract, resolver: resolver))</div>"
        }
        card += "</li>\n"
        return card
    }

    // MARK: Relationships

    /// Render the relationships (conformances, sub/superclasses) as a single
    /// "Relationships" section with a sub-list per relationship kind. Only the
    /// section heading goes in the page TOC (matching DocC's on-page nav).
    private func renderRelationships(
        _ sections: [RelationshipsSection],
        resolver: DocCLinkResolver,
        slugger: Slugger,
        toc: inout [TOCEntry]
    ) -> String {
        let populated = sections.filter { !$0.identifiers.isEmpty }
        guard !populated.isEmpty else { return "" }

        toc.append(TOCEntry(level: 2, id: "relationships", title: "Relationships"))
        var out = "<section class=\"docc-relationships\">\n<h2 id=\"relationships\">Relationships</h2>\n"
        for section in populated {
            if let title = section.title {
                let groupID = slugger.slug(for: title)
                out += "<h3 id=\"\(HTMLEscaping.attribute(groupID))\">\(HTMLEscaping.text(title))</h3>\n"
            }
            out += "<ul class=\"docc-relationship-list\">\n"
            for identifier in section.identifiers {
                out += "<li>\(renderRelationshipMember(identifier, resolver: resolver))</li>\n"
            }
            out += "</ul>\n"
        }
        out += "</section>\n"
        return out
    }

    /// One related symbol: a link when it's a documented topic, otherwise plain
    /// inline code (external symbols like `Swift.Sendable` resolve to an
    /// unresolvable reference carrying only a title).
    private func renderRelationshipMember(_ identifier: String, resolver: DocCLinkResolver) -> String {
        if let link = resolver.resolveTopic(identifier) {
            let inner = link.isSymbol ? "<code>\(HTMLEscaping.text(link.title))</code>" : HTMLEscaping.text(link.title)
            return "<a class=\"docc-symbol-link\" href=\"\(HTMLEscaping.attribute(link.href))\">\(inner)</a>"
        }
        if let title = resolver.title(for: identifier) {
            return "<code>\(HTMLEscaping.text(title))</code>"
        }
        let fallback = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return "<code>\(HTMLEscaping.text(fallback))</code>"
    }
}

// MARK: - Inline rendering

/// Renders DocC inline content to HTML. Pure (no headings/slug state), so it's a
/// namespace of static helpers shared by the block renderer and the sections.
enum DocCInline {
    static func render(_ inlines: [RenderInlineContent], resolver: DocCLinkResolver) -> String {
        var out = ""
        for inline in inlines { out += render(inline, resolver: resolver) }
        return out
    }

    static func render(_ inline: RenderInlineContent, resolver: DocCLinkResolver) -> String {
        switch inline {
        case .text(let text):
            return HTMLEscaping.text(text)
        case .codeVoice(let code):
            return "<code>\(HTMLEscaping.text(code))</code>"
        case .emphasis(let children):
            return "<em>\(render(children, resolver: resolver))</em>"
        case .strong(let children):
            return "<strong>\(render(children, resolver: resolver))</strong>"
        case .strikethrough(let children):
            return "<del>\(render(children, resolver: resolver))</del>"
        case .reference(let identifier, let isActive, let overridingTitle, let overridingInlines):
            return renderReference(identifier, isActive: isActive, overridingTitle: overridingTitle,
                                   overridingInlines: overridingInlines, resolver: resolver)
        case .image(let identifier, let metadata):
            guard let url = resolver.imageURL(identifier) else { return "" }
            let alt = metadata?.abstract.map(plainText) ?? resolver.imageAlt(identifier) ?? ""
            return "<img src=\"\(HTMLEscaping.attribute(url))\" alt=\"\(HTMLEscaping.attribute(alt))\" />"
        case .link(let title, let destination):
            let text = title.map(HTMLEscaping.text) ?? HTMLEscaping.text(destination)
            return "<a href=\"\(HTMLEscaping.attribute(destination))\">\(text)</a>"
        case .unknown:
            return "" // recorded at decode time
        }
    }

    private static func renderReference(
        _ identifier: String,
        isActive: Bool,
        overridingTitle: String?,
        overridingInlines: [RenderInlineContent]?,
        resolver: DocCLinkResolver
    ) -> String {
        // The link text: overriding inline content, then an overriding title,
        // then the reference's own title.
        func text(default fallback: String) -> String {
            if let overridingInlines, !overridingInlines.isEmpty { return render(overridingInlines, resolver: resolver) }
            if let overridingTitle { return HTMLEscaping.text(overridingTitle) }
            return HTMLEscaping.text(fallback)
        }

        if let link = resolver.resolveTopic(identifier) {
            let inner = link.isSymbol ? "<code>\(text(default: link.title))</code>" : text(default: link.title)
            guard isActive else { return inner }
            return "<a class=\"docc-symbol-link\" href=\"\(HTMLEscaping.attribute(link.href))\">\(inner)</a>"
        }
        // An external hyperlink (DocC `link` reference): a plain anchor to the
        // absolute URL, matching the inline `.link` markdown case.
        if let external = resolver.resolveLink(identifier) {
            let inner = text(default: external.title)
            guard isActive else { return inner }
            return "<a href=\"\(HTMLEscaping.attribute(external.href))\">\(inner)</a>"
        }
        // Not a linkable topic (unresolvable, or topic without a URL): render text.
        return text(default: resolver.title(for: identifier) ?? "")
    }

    /// Concatenate inline content into plain text (for abstracts/alt text).
    static func plainText(_ inlines: [RenderInlineContent]) -> String {
        var out = ""
        for inline in inlines {
            switch inline {
            case .text(let text): out += text
            case .codeVoice(let code): out += code
            case .emphasis(let c), .strong(let c), .strikethrough(let c): out += plainText(c)
            case .reference(let id, _, let overridingTitle, let overridingInlines):
                if let overridingInlines, !overridingInlines.isEmpty { out += plainText(overridingInlines) }
                else { out += overridingTitle ?? "" }
                _ = id
            case .link(let title, let destination): out += title ?? destination
            case .image, .unknown: break
            }
        }
        return out
    }
}

// MARK: - Block rendering

/// Renders DocC block content to HTML, sharing a ``Slugger`` so heading anchors
/// stay unique across the page and collecting headings for the table of contents.
struct DocCBlockRenderer {
    let resolver: DocCLinkResolver
    let slugger: Slugger
    private(set) var headings: [TOCEntry] = []
    private(set) var html = ""

    mutating func render(_ blocks: [RenderBlockContent]) {
        for block in blocks { render(block) }
    }

    private mutating func render(_ block: RenderBlockContent) {
        switch block {
        case .paragraph(let inlines):
            html += "<p>\(DocCInline.render(inlines, resolver: resolver))</p>\n"

        case .heading(let level, let text, let anchor):
            let id = anchor ?? slugger.slug(for: text)
            headings.append(TOCEntry(level: level, id: id, title: text))
            html += "<h\(level) id=\"\(HTMLEscaping.attribute(id))\">\(HTMLEscaping.text(text))</h\(level)>\n"

        case .codeListing(let syntax, let code):
            let languageAttr = syntax.map { " class=\"language-\(HTMLEscaping.attribute($0))\"" } ?? ""
            html += "<pre><code\(languageAttr)>\(HTMLEscaping.text(code.joined(separator: "\n")))</code></pre>\n"

        case .aside(let style, let name, let content):
            // Reuse Kiln's admonition markup/CSS for DocC asides.
            var inner = DocCBlockRenderer(resolver: resolver, slugger: slugger)
            inner.render(content)
            headings += inner.headings
            let title = name ?? style.capitalizedFirstLetter
            html += "<div class=\"admonition \(HTMLEscaping.attribute(style))\">\n"
            html += "<p class=\"admonition-title\">\(HTMLEscaping.text(title))</p>\n"
            html += inner.html
            html += "</div>\n"

        case .unorderedList(let items):
            html += "<ul>\n"
            for item in items { renderListItem(item) }
            html += "</ul>\n"

        case .orderedList(let items, let startIndex):
            let startAttr = startIndex.map { " start=\"\($0)\"" } ?? ""
            html += "<ol\(startAttr)>\n"
            for item in items { renderListItem(item) }
            html += "</ol>\n"

        case .table(let header, let rows):
            renderTable(header: header, rows: rows)

        case .termList(let items):
            html += "<dl>\n"
            for item in items {
                html += "<dt>\(DocCInline.render(item.term.inlineContent, resolver: resolver))</dt>\n"
                var inner = DocCBlockRenderer(resolver: resolver, slugger: slugger)
                inner.render(item.definition.content)
                headings += inner.headings
                html += "<dd>\(inner.html)</dd>\n"
            }
            html += "</dl>\n"

        case .links(_, let identifiers):
            html += "<ul class=\"docc-links\">\n"
            for identifier in identifiers {
                guard let link = resolver.resolveTopic(identifier) else { continue }
                html += "<li><a href=\"\(HTMLEscaping.attribute(link.href))\">\(HTMLEscaping.text(link.title))</a></li>\n"
            }
            html += "</ul>\n"

        case .thematicBreak:
            html += "<hr>\n"

        case .unknown:
            break // recorded at decode time
        }
    }

    private mutating func renderListItem(_ item: RenderListItem) {
        var inner = DocCBlockRenderer(resolver: resolver, slugger: slugger)
        inner.render(item.content)
        headings += inner.headings
        html += "<li>\(inner.html)</li>\n"
    }

    private mutating func renderTable(header: String?, rows: [[[RenderBlockContent]]]) {
        html += "<table>\n"
        var bodyRows = rows
        if header == "row" || header == "both", let headerRow = rows.first {
            html += "<thead>\n<tr>\n"
            for cell in headerRow { html += "<th>\(renderCell(cell))</th>\n" }
            html += "</tr>\n</thead>\n"
            bodyRows = Array(rows.dropFirst())
        }
        html += "<tbody>\n"
        for row in bodyRows {
            html += "<tr>\n"
            for cell in row { html += "<td>\(renderCell(cell))</td>\n" }
            html += "</tr>\n"
        }
        html += "</tbody>\n</table>\n"
    }

    /// Render a table cell's blocks (cell headings are not added to the page TOC).
    private func renderCell(_ cell: [RenderBlockContent]) -> String {
        var inner = DocCBlockRenderer(resolver: resolver, slugger: slugger)
        inner.render(cell)
        return inner.html
    }
}
