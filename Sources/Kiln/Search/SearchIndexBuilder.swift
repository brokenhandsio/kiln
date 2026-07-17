#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A single searchable document.
struct SearchDocument: Codable {
    var location: String
    var title: String
    var text: String
    /// An optional document kind (e.g. `"module"` for a DocC module landing
    /// page). The client boosts and badges kinds it knows about; omitted from
    /// the JSON when `nil`, so plain markdown pages carry no dead weight.
    var kind: String?
}

/// The search index emitted per language and consumed by the client-side
/// search (`search.js` builds a lunr index from it in the browser).
struct SearchIndex: Codable {
    var docs: [SearchDocument]
}

/// Accumulates searchable documents and serialises them to JSON.
struct SearchIndexBuilder {
    private(set) var documents: [SearchDocument] = []

    /// Add a page to the index.
    /// - Parameters:
    ///   - location: site-relative URL of the page (e.g. `install/macos/`).
    ///   - title: the page title.
    ///   - html: the rendered HTML body (stripped to plain text for indexing).
    ///   - kind: an optional document kind (see ``SearchDocument/kind``).
    mutating func add(location: String, title: String, html: String, kind: String? = nil) {
        documents.append(SearchDocument(
            location: location,
            title: title,
            text: SearchIndexBuilder.plainText(from: html),
            kind: kind
        ))
    }

    /// Add a pre-built document (e.g. merging a persisted search fragment).
    mutating func add(document: SearchDocument) {
        documents.append(document)
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(SearchIndex(docs: documents))
    }

    /// Strip HTML tags and collapse whitespace to produce indexable text.
    static func plainText(from html: String) -> String {
        var text = ""
        var insideTag = false
        for character in html {
            switch character {
            case "<": insideTag = true
            case ">": insideTag = false; text.append(" ")
            default: if !insideTag { text.append(character) }
            }
        }
        text = text
            .replacing("&amp;", with: "&")
            .replacing("&lt;", with: "<")
            .replacing("&gt;", with: ">")
            .replacing("&quot;", with: "\"")
            .replacing("&#39;", with: "'")
        // Collapse runs of whitespace.
        let collapsed = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        return collapsed.joined(separator: " ")
    }
}
