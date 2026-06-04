import Testing
@testable import Kiln

@Suite("llms.txt generation")
struct LLMSTextTests {
    @Test("Index renders title, summary and H2 sections of links")
    func index() {
        let text = LLMSText.index(
            title: "My Docs",
            summary: "A short summary.",
            sections: [
                .init(title: nil, links: [.init(title: "Welcome", url: "https://x.com/index.md")]),
                .init(title: "Guides", links: [
                    .init(title: "Config", url: "https://x.com/guides/config/index.md"),
                ]),
            ]
        )
        #expect(text.hasPrefix("# My Docs\n"))
        #expect(text.contains("> A short summary."))
        #expect(text.contains("## Documentation\n\n- [Welcome](https://x.com/index.md)"))
        #expect(text.contains("## Guides\n\n- [Config](https://x.com/guides/config/index.md)"))
    }

    @Test("Full corpus concatenates page markdown with source markers")
    func full() {
        let text = LLMSText.full(
            title: "My Docs",
            summary: nil,
            pages: [
                .init(url: "https://x.com/", body: "# Home\n\nHello."),
                .init(url: "https://x.com/guides/config/", body: "# Config\n\nDetails."),
            ]
        )
        #expect(text.contains("<!-- Source: https://x.com/ -->"))
        #expect(text.contains("# Home\n\nHello."))
        #expect(text.contains("<!-- Source: https://x.com/guides/config/ -->"))
        #expect(text.contains("# Config\n\nDetails."))
    }
}
