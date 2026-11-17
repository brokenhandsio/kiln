import Foundation
import Testing
@testable import Kiln

@Suite("Search index")
struct SearchIndexTests {
    @Test("Document keys are serialised in a stable, sorted order")
    func sortedKeys() throws {
        var builder = SearchIndexBuilder()
        builder.add(location: "install/", title: "Install", html: "<p>Get started</p>", kind: "page")
        let json = try #require(String(data: builder.jsonData(), encoding: .utf8))
        // JSONEncoder otherwise writes keys in per-process hash order, so the
        // file would differ between two builds of identical content.
        #expect(json == #"{"docs":[{"kind":"page","location":"install/","text":"Get started","title":"Install"}]}"#)
    }
}
