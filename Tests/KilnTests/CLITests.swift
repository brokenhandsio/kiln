import Testing
import Kiln
import ArgumentParser
@testable import KilnCLI

@Suite("Static file server path resolution")
struct StaticFileServerTests {
    @Test("Root and directory paths resolve to index.html")
    func directoryPaths() {
        #expect(StaticFileServer.relativePath(forURI: "/") == "index.html")
        #expect(StaticFileServer.relativePath(forURI: "/basics/routing/") == "basics/routing/index.html")
        // Extensionless paths are treated as directories.
        #expect(StaticFileServer.relativePath(forURI: "/basics/routing") == "basics/routing/index.html")
    }

    @Test("Files with extensions are served as-is")
    func filePaths() {
        #expect(StaticFileServer.relativePath(forURI: "/llms.txt") == "llms.txt")
        #expect(StaticFileServer.relativePath(forURI: "/_kiln/css/theme.css") == "_kiln/css/theme.css")
        #expect(StaticFileServer.relativePath(forURI: "/sitemap.xml") == "sitemap.xml")
    }

    @Test("Query strings and fragments are stripped")
    func queryAndFragment() {
        #expect(StaticFileServer.relativePath(forURI: "/search/?q=hello") == "search/index.html")
        #expect(StaticFileServer.relativePath(forURI: "/page#anchor") == "page/index.html")
    }

    @Test("Path traversal is rejected")
    func traversalRejected() {
        #expect(StaticFileServer.relativePath(forURI: "/../etc/passwd") == nil)
        #expect(StaticFileServer.relativePath(forURI: "/foo/../../secret") == nil)
        // A contained `..` is resolved, not rejected.
        #expect(StaticFileServer.relativePath(forURI: "/foo/../bar/") == "bar/index.html")
    }

    @Test("Percent-encoded paths are decoded")
    func percentDecoding() {
        #expect(StaticFileServer.relativePath(forURI: "/a%20b/") == "a b/index.html")
    }

    @Test("Content types map from extensions")
    func contentTypes() {
        #expect(StaticFileServer.contentType(forExtension: "html") == "text/html; charset=utf-8")
        #expect(StaticFileServer.contentType(forExtension: "CSS") == "text/css; charset=utf-8")
        #expect(StaticFileServer.contentType(forExtension: "js") == "text/javascript; charset=utf-8")
        #expect(StaticFileServer.contentType(forExtension: "json") == "application/json; charset=utf-8")
        #expect(StaticFileServer.contentType(forExtension: "svg") == "image/svg+xml")
        #expect(StaticFileServer.contentType(forExtension: "woff2") == "font/woff2")
        #expect(StaticFileServer.contentType(forExtension: "unknown") == "application/octet-stream")
    }
}

@Suite("Scaffold generation")
struct ScaffoldTests {
    let input = ScaffoldInput(
        targetName: "MyDocs",
        siteName: "My Docs",
        url: "https://docs.example.com",
        defaultLanguage: .init(code: .english, literal: ".english"),
        otherLanguages: [
            .init(code: .german, literal: ".german"),
            .init(code: .french, literal: ".french"),
        ]
    )

    @Test("Package.swift references the target and kiln dependency")
    func packageSwift() {
        let package = Scaffold.packageSwift(input: input)
        #expect(package.contains("name: \"MyDocs\""))
        #expect(package.contains("https://github.com/brokenhandsio/kiln.git"))
        #expect(package.contains(".product(name: \"Kiln\", package: \"kiln\")"))
    }

    @Test("main.swift emits the chosen languages and site config")
    func mainSwift() {
        let main = Scaffold.mainSwift(input: input)
        #expect(main.contains("name: \"My Docs\""))
        #expect(main.contains("url: \"https://docs.example.com\""))
        #expect(main.contains("Language(.english, isDefault: true),"))
        #expect(main.contains("Language(.german),"))
        #expect(main.contains("Language(.french),"))
        #expect(main.contains("contentDirectory: \"Content\", outputDirectory: \"site\""))
    }

    @Test("gitignore excludes build artefacts and output")
    func gitignore() {
        let gitignore = Scaffold.gitignore()
        #expect(gitignore.contains(".build/"))
        #expect(gitignore.contains("site/"))
    }
}

@Suite("new command argument parsing")
struct NewCommandParsingTests {
    @Test("Parses path, options and repeated/comma-separated languages")
    func parsesOptions() throws {
        let command = try New.parse([
            "my-docs",
            "--name", "My Docs",
            "--url", "https://docs.example.com",
            "--default-language", "en",
            "--language", "de",
            "--language", "fr,pt-BR",
            "--non-interactive",
        ])
        #expect(command.path == "my-docs")
        #expect(command.name == "My Docs")
        #expect(command.url == "https://docs.example.com")
        #expect(command.defaultLanguage == "en")
        #expect(command.languages == ["de", "fr,pt-BR"])
        #expect(command.nonInteractive)
    }

    @Test("Defaults: no languages, interactive (non-interactive off)")
    func parsesDefaults() throws {
        let command = try New.parse([])
        #expect(command.path == nil)
        #expect(command.languages.isEmpty)
        #expect(command.nonInteractive == false)
    }

    @Test("-y is a short alias for --non-interactive")
    func shortNonInteractive() throws {
        let command = try New.parse(["-y"])
        #expect(command.nonInteractive)
    }
}
