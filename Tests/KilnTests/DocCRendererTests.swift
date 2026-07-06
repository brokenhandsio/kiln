import Testing
import Foundation
@testable import Kiln

/// Renders real Queues nodes and synthetic nodes through ``DocCRenderer`` and
/// asserts the emitted HTML. Fixtures cover the common path (declaration,
/// abstract, parameters, discussion); synthetic nodes cover constructs the small
/// Queues archive doesn't exercise (asides, tables, inline symbol references) and
/// the path mapper.
@Suite("DocC rendering")
struct DocCRendererTests {
    private func node(_ archive: String, _ relativePath: String) throws -> RenderNode {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            Issue.record("Could not locate the Fixtures resource")
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        let file = fixtures.appendingPathComponent("docc/\(archive).doccarchive/data/\(relativePath)")
        return try JSONDecoder().decode(RenderNode.self, from: Data(contentsOf: file))
    }

    /// Decode a synthetic RenderNode from an inline JSON string.
    private func decode(_ json: String) throws -> RenderNode {
        try JSONDecoder().decode(RenderNode.self, from: Data(json.utf8))
    }

    @Test("A method page renders abstract, linked declaration, parameters, and TOC")
    func rendersMethod() throws {
        let node = try node("Queues", "documentation/queues/queue/dispatch(_:_:maxretrycount:delayuntil:id:)-630ll.json")
        let rendered = DocCRenderer().render(node)

        #expect(rendered.title == "dispatch(_:_:maxRetryCount:delayUntil:id:)")
        #expect(rendered.roleHeading == "Instance Method")
        #expect(rendered.symbolKind == "method")

        let html = rendered.contentHTML
        // Abstract.
        #expect(rendered.abstractText == "Dispatch a job into the queue for processing")
        #expect(html.contains("docc-abstract"))
        #expect(html.contains("Dispatch a job into the queue for processing"))
        // Declaration with a keyword token and a linked type (Job / JobIdentifier).
        #expect(html.contains("<pre class=\"declaration\">"))
        #expect(html.contains("<span class=\"token-keyword\">func</span>"))
        #expect(html.contains("href=\"/documentation/queues/job\""))
        // Parameters section, first param + its prose.
        #expect(html.contains("<h2 id=\"parameters\">Parameters</h2>"))
        #expect(html.contains("<dt class=\"docc-parameter-name\"><code>job</code></dt>"))
        #expect(html.contains("The Job type"))

        // TOC has the generated Parameters entry.
        #expect(rendered.tableOfContents.contains { $0.id == "parameters" && $0.title == "Parameters" })
    }

    @Test("The module landing renders discussion heading + list")
    func rendersModuleLanding() throws {
        let node = try node("Queues", "documentation/queues.json")
        let rendered = DocCRenderer().render(node)

        let html = rendered.contentHTML
        // The discussion "Overview" heading uses DocC's own anchor.
        #expect(html.contains("<h2 id=\"overview\">Overview</h2>"))
        #expect(html.contains("<ul>"))
        #expect(html.contains("Sending emails outside of the main request thread"))
        // And it lands in the TOC.
        #expect(rendered.tableOfContents.contains { $0.id == "overview" })
    }

    @Test("Every Queues + XCTQueues node renders without throwing")
    func rendersWholeCorpus() throws {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        let renderer = DocCRenderer()
        var rendered = 0
        for archive in ["Queues", "XCTQueues"] {
            let dataDir = fixtures.appendingPathComponent("docc/\(archive).doccarchive/data")
            let files = (FileManager.default.enumerator(at: dataDir, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }) ?? []
            for file in files {
                let node = try JSONDecoder().decode(RenderNode.self, from: Data(contentsOf: file))
                let out = renderer.render(node)
                // Every page has a title and produced some body.
                #expect(!out.title.isEmpty || node.kind != .symbol)
                rendered += 1
            }
        }
        #expect(rendered == 307)
    }

    @Test("Inline symbol references render as code links; the path mapper is applied")
    func rendersInlineReference() throws {
        let node = try decode("""
        {
          "schemaVersion": {"major": 0, "minor": 3, "patch": 0},
          "identifier": {"url": "doc://T/documentation/T/X", "interfaceLanguage": "swift"},
          "kind": "symbol",
          "metadata": {"title": "X", "roleHeading": "Structure", "symbolKind": "struct"},
          "abstract": [{"type": "text", "text": "See "},
                       {"type": "reference", "identifier": "doc://T/documentation/T/Queue", "isActive": true},
                       {"type": "text", "text": " and "},
                       {"type": "reference", "identifier": "doc://T/documentation/T/Guide", "isActive": true}],
          "primaryContentSections": [],
          "references": {
            "doc://T/documentation/T/Queue": {"type": "topic", "identifier": "doc://T/documentation/T/Queue",
               "kind": "symbol", "title": "Queue", "url": "/documentation/t/queue"},
            "doc://T/documentation/T/Guide": {"type": "topic", "identifier": "doc://T/documentation/T/Guide",
               "kind": "article", "role": "article", "title": "The Guide", "url": "/documentation/t/guide"}
          }
        }
        """)

        // Path mapper prefixes each archive URL with the module mount.
        let rendered = DocCRenderer(pathMapper: { "/t\($0)/" }).render(node)
        let html = rendered.contentHTML
        // Symbol reference → inline code inside the link, URL rewritten.
        #expect(html.contains("<a class=\"docc-symbol-link\" href=\"/t/documentation/t/queue/\"><code>Queue</code></a>"))
        // Article reference → plain text link (no <code>).
        #expect(html.contains("<a class=\"docc-symbol-link\" href=\"/t/documentation/t/guide/\">The Guide</a>"))
        #expect(!html.contains("<code>The Guide</code>"))
    }

    @Test("Discussion asides, code listings, and tables render")
    func rendersRichBlocks() throws {
        let node = try decode("""
        {
          "schemaVersion": {"major": 0, "minor": 3, "patch": 0},
          "identifier": {"url": "doc://T/documentation/T/X", "interfaceLanguage": "swift"},
          "kind": "article",
          "metadata": {"title": "X"},
          "primaryContentSections": [
            {"kind": "content", "content": [
              {"type": "aside", "style": "warning", "name": "Careful",
               "content": [{"type": "paragraph", "inlineContent": [{"type": "text", "text": "Mind the gap."}]}]},
              {"type": "codeListing", "syntax": "swift", "code": ["let x = 1", "print(x)"]},
              {"type": "table", "header": "row", "rows": [
                [[{"type": "paragraph", "inlineContent": [{"type": "text", "text": "Name"}]}],
                 [{"type": "paragraph", "inlineContent": [{"type": "text", "text": "Type"}]}]],
                [[{"type": "paragraph", "inlineContent": [{"type": "text", "text": "id"}]}],
                 [{"type": "paragraph", "inlineContent": [{"type": "text", "text": "Int"}]}]]
              ]}
            ]}
          ],
          "references": {}
        }
        """)

        let html = DocCRenderer().render(node).contentHTML
        // Aside reuses the admonition markup (so it inherits Kiln's CSS).
        #expect(html.contains("<div class=\"admonition warning\">"))
        #expect(html.contains("<p class=\"admonition-title\">Careful</p>"))
        #expect(html.contains("Mind the gap."))
        // Code listing joins lines and sets the highlight.js language class.
        #expect(html.contains("<pre><code class=\"language-swift\">let x = 1\nprint(x)</code></pre>"))
        // Table renders a header row + body.
        #expect(html.contains("<thead>"))
        #expect(html.contains("<th>"))
        #expect(html.contains("<td>"))
        #expect(html.contains("Int"))
    }

    @Test("A thematic break renders as <hr>; a mentions section renders 'Mentioned in'")
    func rendersThematicBreakAndMentions() throws {
        let node = try decode("""
        {
          "schemaVersion": {"major": 0, "minor": 3, "patch": 0},
          "identifier": {"url": "doc://T/documentation/T/X", "interfaceLanguage": "swift"},
          "kind": "symbol",
          "metadata": {"title": "X"},
          "primaryContentSections": [
            {"kind": "mentions", "mentions": ["doc://T/documentation/T/guide", "doc://T/documentation/T/missing"]},
            {"kind": "content", "content": [
              {"type": "paragraph", "inlineContent": [{"type": "text", "text": "Before."}]},
              {"type": "thematicBreak"},
              {"type": "paragraph", "inlineContent": [{"type": "text", "text": "After."}]}
            ]}
          ],
          "references": {
            "doc://T/documentation/T/guide": {"type": "topic", "identifier": "doc://T/documentation/T/guide",
              "title": "Using T", "url": "/documentation/T/guide", "kind": "article"}
          }
        }
        """)

        let html = DocCRenderer().render(node).contentHTML
        // Thematic break → a horizontal rule between the two paragraphs.
        #expect(html.contains("<hr>"))
        // Mentions → a "Mentioned in" section linking the resolvable article; the
        // unresolvable identifier is skipped, not emitted as a broken link.
        #expect(html.contains("docc-mentions"))
        #expect(html.contains("Mentioned in"))
        #expect(html.contains("<a href=\"/documentation/T/guide\">Using T</a>"))
        #expect(!html.contains("missing"))
    }

    @Test("The module landing renders curated Topics as symbol cards")
    func rendersTopics() throws {
        let node = try node("Queues", "documentation/queues.json")
        let rendered = DocCRenderer().render(node)
        let html = rendered.contentHTML

        #expect(html.contains("<h2 id=\"topics\">Topics</h2>"))
        // A curated group heading (DocC's own anchor).
        #expect(html.contains("<h3 id=\"Classes\">Classes</h3>"))
        // A symbol card: code-styled link to the member + its abstract.
        #expect(html.contains("<a class=\"docc-topic-link\" href=\"/documentation/queues/schedulebuilder\"><code>ScheduleBuilder</code></a>"))
        #expect(html.contains("<div class=\"docc-topic-abstract\">"))

        // Topics + its groups are in the TOC (h2 with h3 children).
        let topics = try #require(rendered.tableOfContents.first { $0.id == "topics" })
        #expect(topics.children.contains { $0.title == "Classes" })
    }

    @Test("A conforming struct renders its Relationships section")
    func rendersRelationships() throws {
        let node = try node("Queues", "documentation/queues/jobdata.json")
        let rendered = DocCRenderer().render(node)
        let html = rendered.contentHTML

        #expect(html.contains("<h2 id=\"relationships\">Relationships</h2>"))
        #expect(html.contains("<h3 id=\"conforms-to\">Conforms To</h3>"))
        // External conformances (Decodable/Sendable) resolve to unresolvable refs:
        // rendered as plain inline code, not links.
        #expect(html.contains("<li><code>Swift.Decodable</code></li>"))
        #expect(html.contains("<li><code>Swift.Sendable</code></li>"))
        #expect(rendered.tableOfContents.contains { $0.id == "relationships" })
    }

    @Test("A default-implementation property renders its Default Implementations")
    func rendersDefaultImplementations() throws {
        let node = try node("Queues", "documentation/queues/anyjob/name.json")
        let rendered = DocCRenderer().render(node)
        let html = rendered.contentHTML

        #expect(html.contains("<h2 id=\"default-implementations\">Default Implementations</h2>"))
        #expect(html.contains("AnyJob Implementations"))
        #expect(html.contains("<a class=\"docc-topic-link\" href=\"/documentation/queues/anyjob/name-1r2fj\">"))
        #expect(rendered.tableOfContents.contains { $0.id == "default-implementations" })
    }

    @Test("See Also groups render as symbol cards")
    func rendersSeeAlso() throws {
        let node = try decode("""
        {
          "schemaVersion": {"major": 0, "minor": 3, "patch": 0},
          "identifier": {"url": "doc://T/documentation/T/X", "interfaceLanguage": "swift"},
          "kind": "symbol",
          "metadata": {"title": "X", "symbolKind": "struct"},
          "seeAlsoSections": [
            {"title": "Related", "generated": false, "anchor": "Related",
             "identifiers": ["doc://T/documentation/T/Queue"]}
          ],
          "references": {
            "doc://T/documentation/T/Queue": {"type": "topic", "identifier": "doc://T/documentation/T/Queue",
               "kind": "symbol", "title": "Queue", "url": "/documentation/t/queue",
               "abstract": [{"type": "text", "text": "A queue."}]}
          }
        }
        """)
        let html = DocCRenderer().render(node).contentHTML
        #expect(html.contains("<h2 id=\"see-also\">See Also</h2>"))
        #expect(html.contains("<h3 id=\"Related\">Related</h3>"))
        #expect(html.contains("<a class=\"docc-topic-link\" href=\"/documentation/t/queue\"><code>Queue</code></a>"))
        #expect(html.contains("A queue."))
    }

    @Test("An unresolvable inline reference degrades to its title, not a crash")
    func unresolvableReference() throws {
        let node = try decode("""
        {
          "schemaVersion": {"major": 0, "minor": 3, "patch": 0},
          "identifier": {"url": "doc://T/documentation/T/X", "interfaceLanguage": "swift"},
          "kind": "symbol",
          "metadata": {"title": "X"},
          "abstract": [{"type": "reference", "identifier": "doc://T/Sb", "isActive": false}],
          "references": {
            "doc://T/Sb": {"type": "unresolvable", "identifier": "doc://T/Sb", "title": "Bool"}
          }
        }
        """)
        let html = DocCRenderer().render(node).contentHTML
        #expect(html.contains("Bool"))
        #expect(!html.contains("<a")) // not linkable
    }
}
