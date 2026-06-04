import Testing
@testable import Kiln

@Suite("Locale resolution")
struct LocaleResolutionTests {
    let locales: Set<String> = ["en", "de", "zh"]

    @Test("Files without a locale suffix belong to the default locale")
    func defaultLocale() {
        let (logical, locale) = ContentLoader.resolveLocale(
            relativePath: "install/macos.md", knownLocales: locales, defaultLocale: "en")
        #expect(logical == "install/macos.md")
        #expect(locale == "en")
    }

    @Test("A recognised locale suffix is stripped to the logical path")
    func localeSuffix() {
        let (logical, locale) = ContentLoader.resolveLocale(
            relativePath: "install/macos.de.md", knownLocales: locales, defaultLocale: "en")
        #expect(logical == "install/macos.md")
        #expect(locale == "de")
    }

    @Test("An unrecognised middle segment is treated as part of the name")
    func unknownSegment() {
        let (logical, locale) = ContentLoader.resolveLocale(
            relativePath: "hello.world.md", knownLocales: locales, defaultLocale: "en")
        #expect(logical == "hello.world.md")
        #expect(locale == "en")
    }
}

@Suite("Site URLs")
struct SiteURLTests {
    let urls = SiteURLs(defaultLocale: "en")

    @Test("Pretty paths drop .md and index")
    func prettyPaths() {
        #expect(urls.urlPath(forLogicalPath: "index.md", locale: "en") == "/")
        #expect(urls.urlPath(forLogicalPath: "install/macos.md", locale: "en") == "/install/macos/")
        #expect(urls.urlPath(forLogicalPath: "advanced/index.md", locale: "en") == "/advanced/")
    }

    @Test("Non-default locales are prefixed")
    func localePrefix() {
        #expect(urls.urlPath(forLogicalPath: "index.md", locale: "de") == "/de/")
        #expect(urls.urlPath(forLogicalPath: "install/macos.md", locale: "de") == "/de/install/macos/")
    }
}

@Suite("Front matter")
struct FrontMatterTests {
    @Test("Parses a YAML front-matter block and strips it from the body")
    func parses() {
        let (frontMatter, body) = FrontMatter.parse(from: """
        ---
        title: Custom Title
        description: A summary.
        ---
        # Heading

        Body.
        """)
        #expect(frontMatter.title == "Custom Title")
        #expect(frontMatter.description == "A summary.")
        #expect(body.hasPrefix("# Heading"))
    }

    @Test("Documents without front matter are returned unchanged")
    func noFrontMatter() {
        let (frontMatter, body) = FrontMatter.parse(from: "# Just a heading")
        #expect(frontMatter == .empty)
        #expect(body == "# Just a heading")
    }
}
