import Testing
import Foundation
import LeafKit
@testable import Kiln

@Suite("Custom Leaf tags")
struct CustomTagTests {

    struct ShoutTag: LeafTag {
        func render(_ ctx: LeafContext) throws -> LeafData {
            try ctx.requireParameterCount(1)
            return .string((ctx.parameters[0].string ?? "").uppercased() + "!")
        }
    }

    @Test("A caller-registered tag renders in templates")
    func callerTagRenders() async throws {
        let html = try await renderFooter(
            "<footer>#shout(\"hello\")</footer>",
            leafTags: ["shout": ShoutTag()]
        )
        #expect(html.contains("HELLO!"))
    }

    private func renderFooter(_ footer: String, leafTags: [String: any LeafTag]) async throws -> String {
        let shared = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-theme-\(UUID().uuidString)")
        let partials = shared.appendingPathComponent("templates/partials")
        try FileManager.default.createDirectory(at: partials, withIntermediateDirectories: true)
        try footer.write(to: partials.appendingPathComponent("footer.leaf"), atomically: true, encoding: .utf8)

        let content = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-content-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try "# Home\n\nHello.".write(to: content.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-out-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: shared)
            try? FileManager.default.removeItem(at: content)
            try? FileManager.default.removeItem(at: output)
        }

        let site = KilnSite(
            name: "Custom Tag Test",
            url: "https://example.com",
            description: "Tag hook test.",
            theme: .default(sharedLayers: [shared]),
            languages: [.init(.english, isDefault: true)]
        ) {
            Page("Home", "index.md")
        }
        try await Kiln.build(site, contentDirectory: content, outputDirectory: output, linkChecking: .off, leafTags: leafTags)
        return try String(contentsOf: output.appendingPathComponent("index.html"), encoding: .utf8)
    }
}
