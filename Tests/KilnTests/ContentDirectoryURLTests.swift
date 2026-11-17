import Testing
import Foundation
@testable import Kiln

/// A content directory URL with no trailing slash — what a caller gets from
/// `URL(fileURLWithPath:)` when the directory doesn't exist yet, or from
/// `appendingPathComponent` without `isDirectory:` — must still resolve
/// subdirectories inside it, not beside it.
@Suite("Content directory URLs")
struct ContentDirectoryURLTests {

    @Test("Relative paths resolve inside a directory, with or without its trailing slash")
    func appendingDirectoryPath() {
        let bare = URL(fileURLWithPath: "/site/content", isDirectory: false)
        let slashed = URL(fileURLWithPath: "/site/content", isDirectory: true)
        #expect(bare.appendingDirectoryPath("posts").path == "/site/content/posts")
        #expect(slashed.appendingDirectoryPath("posts").path == "/site/content/posts")
        #expect(bare.appendingDirectoryPath("archives/api").path == "/site/content/archives/api")
    }

    @Test("Blog posts load from a content directory URL without a trailing slash")
    func blogPosts() async throws {
        try await withContent([
            "index.md": "# Home",
            "posts/hello.md": "---\ntitle: Hello\ndate: 2025-01-01 09:00\n---\n\nHello.",
        ]) { content, output in
            let site = KilnSite(name: "Blog", url: "https://example.com", blog: Blog())
            try await Kiln.build(site, contentDirectory: content, outputDirectory: output, linkChecking: .off)
            #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("posts/hello/index.html").path))
        }
    }

    @Test("A version's content directory resolves inside a content directory URL without a trailing slash")
    func versionContent() async throws {
        try await withContent(["main/index.md": "# Main home"]) { content, output in
            let site = KilnSite(
                name: "Versioned", url: "https://example.com",
                versions: [
                    DocVersion(id: "main", name: "Main", isDefault: true, contentDirectory: "main") {
                        Page("Home", "index.md")
                    }
                ]
            )
            try await Kiln.build(site, contentDirectory: content, outputDirectory: output, linkChecking: .off)
            let home = try String(contentsOf: output.appendingPathComponent("index.html"), encoding: .utf8)
            #expect(home.contains("Main home"))
        }
    }

    /// Write `files` into a fresh content directory and hand the body a URL to
    /// it that has no trailing slash, plus an output directory.
    private func withContent(
        _ files: [String: String],
        _ body: (_ content: URL, _ output: URL) async throws -> Void
    ) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("kiln-content-url-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        for (path, contents) in files {
            let file = root.appendingPathComponent("content/\(path)")
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        let content = URL(fileURLWithPath: root.appendingPathComponent("content").path, isDirectory: false)
        #expect(!content.absoluteString.hasSuffix("/"))
        try await body(content, root.appendingPathComponent("output", isDirectory: true))
    }
}
