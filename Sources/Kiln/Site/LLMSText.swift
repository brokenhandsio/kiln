/// Generates AI/agent-friendly index files following the
/// [llms.txt](https://llmstxt.org) convention:
///
/// - **`llms.txt`** — a structured index: an H1 title, a `>` summary, then H2
///   sections each listing links (to the per-page markdown).
/// - **`llms-full.txt`** — the full documentation corpus: every page's markdown
///   concatenated, so a model can ingest the whole site in one request.
enum LLMSText {
    /// A link in the `llms.txt` index.
    struct Link {
        var title: String
        var url: String
    }

    /// An H2 section of the index (a `nil` title renders as "Documentation").
    struct Section {
        var title: String?
        var links: [Link]
    }

    /// A page's markdown for `llms-full.txt`.
    struct Page {
        var url: String
        var body: String
    }

    static func index(title: String, summary: String?, sections: [Section]) -> String {
        var out = "# \(title)\n"
        if let summary, !summary.isEmpty {
            out += "\n> \(summary)\n"
        }
        for section in sections where !section.links.isEmpty {
            out += "\n## \(section.title ?? "Documentation")\n\n"
            for link in section.links {
                out += "- [\(link.title)](\(link.url))\n"
            }
        }
        return out
    }

    static func full(title: String, summary: String?, pages: [Page]) -> String {
        var out = "# \(title)\n"
        if let summary, !summary.isEmpty {
            out += "\n> \(summary)\n"
        }
        for page in pages {
            out += "\n\n<!-- Source: \(page.url) -->\n\n"
            out += page.body.trimmedWhitespace()
            out += "\n"
        }
        return out
    }
}
