import Testing
@testable import Kiln

@Suite("Markdown rendering")
struct MarkdownTests {
    let renderer = MarkdownRenderer()

    @Test("Images render with alt and are lazy-loaded")
    func imageLazyLoading() {
        let result = renderer.render("![A diagram](/img/diagram.png)")
        #expect(result.html.contains("<img"))
        #expect(result.html.contains("src=\"/img/diagram.png\""))
        #expect(result.html.contains("alt=\"A diagram\""))
        #expect(result.html.contains("loading=\"lazy\""))
        #expect(result.html.contains("decoding=\"async\""))
    }

    @Test("Admonitions render with kind and title")
    func admonitionWithTitle() {
        let result = renderer.render("""
        !!! tip "Heads up"
            Body text here.
        """)
        #expect(result.html.contains("<div class=\"admonition tip\">"))
        #expect(result.html.contains("<p class=\"admonition-title\">Heads up</p>"))
        #expect(result.html.contains("Body text here."))
    }

    @Test("Admonitions without a title use the capitalised kind")
    func admonitionDefaultTitle() {
        let result = renderer.render("""
        !!! warning
            Careful!
        """)
        #expect(result.html.contains("<div class=\"admonition warning\">"))
        #expect(result.html.contains("<p class=\"admonition-title\">Warning</p>"))
    }

    @Test("Collapsible admonitions render as details/summary")
    func collapsibleAdmonition() {
        let result = renderer.render("""
        ???+ info "More"
            Hidden detail.
        """)
        #expect(result.html.contains("<details class=\"admonition info\" open>"))
        #expect(result.html.contains("<summary class=\"admonition-title\">More</summary>"))
    }

    @Test("Headings get slugged ids, permalinks and a table of contents")
    func headingsAndTOC() {
        let result = renderer.render("""
        # Title

        ## First Section

        ### Nested

        ## Second Section
        """)
        #expect(result.html.contains("<h2 id=\"first-section\">"))
        #expect(result.html.contains("class=\"headerlink\""))
        #expect(result.firstHeading == "Title")

        // toc covers levels 2...3 by default: two top-level entries, one nested.
        #expect(result.tableOfContents.count == 2)
        #expect(result.tableOfContents.first?.id == "first-section")
        #expect(result.tableOfContents.first?.children.first?.title == "Nested")
    }

    @Test("Tables render as HTML tables")
    func tables() {
        let result = renderer.render("""
        | A | B |
        | - | - |
        | 1 | 2 |
        """)
        #expect(result.html.contains("<table>"))
        #expect(result.html.contains("<th>A</th>"))
        #expect(result.html.contains("<td>1</td>"))
    }

    @Test("HTML special characters in text and code are escaped")
    func escaping() {
        // Note: `<tag>` in prose is valid CommonMark raw HTML, so we use
        // characters that are unambiguously text: `<` followed by a space, and
        // a bare ampersand.
        let result = renderer.render("A `<tag>` and a comparison a < b and x & y.")
        #expect(result.html.contains("<code>&lt;tag&gt;</code>"))
        #expect(result.html.contains("a &lt; b"))
        #expect(result.html.contains("x &amp; y"))
    }

    @Test("Code blocks carry a language class")
    func codeBlockLanguage() {
        let result = renderer.render("""
        ```swift
        let x = 1
        ```
        """)
        #expect(result.html.contains("<code class=\"language-swift\">"))
    }
}

@Suite("Slugger")
struct SluggerTests {
    @Test("Produces GitHub-style slugs")
    func basic() {
        let slugger = Slugger()
        #expect(slugger.slug(for: "Hello, World!") == "hello-world")
    }

    @Test("Disambiguates repeated headings")
    func unique() {
        let slugger = Slugger()
        #expect(slugger.slug(for: "Overview") == "overview")
        #expect(slugger.slug(for: "Overview") == "overview-1")
        #expect(slugger.slug(for: "Overview") == "overview-2")
    }
}
