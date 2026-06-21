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

    @Test("Base path is normalised to a leading slash with no trailing slash")
    func normaliseBasePath() {
        #expect(SiteURLs.normaliseBasePath("") == "")
        #expect(SiteURLs.normaliseBasePath("/") == "")
        #expect(SiteURLs.normaliseBasePath("docs") == "/docs")
        #expect(SiteURLs.normaliseBasePath("/docs") == "/docs")
        #expect(SiteURLs.normaliseBasePath("/docs/") == "/docs")
        #expect(SiteURLs.normaliseBasePath("docs/guide/") == "/docs/guide")
    }

    @Test("A base path prefixes page, search, and asset URLs")
    func basePathPrefix() {
        let urls = SiteURLs(defaultLocale: "en", basePath: "/docs")
        #expect(urls.basePath == "/docs")
        #expect(urls.urlPath(forLogicalPath: "index.md", locale: "en") == "/docs/")
        #expect(urls.urlPath(forLogicalPath: "install/macos.md", locale: "en") == "/docs/install/macos/")
        #expect(urls.urlPath(forLogicalPath: "index.md", locale: "de") == "/docs/de/")
        #expect(urls.searchIndexURLPath(forLocale: "en") == "/docs/search/search_index.json")
    }

    @Test("A version prefix composes with the base path")
    func basePathWithVersion() {
        let urls = SiteURLs(defaultLocale: "en", versionPrefix: "4.0/", basePath: "docs")
        #expect(urls.urlPath(forLogicalPath: "install/macos.md", locale: "en") == "/docs/4.0/install/macos/")
    }

    @Test("The relative baseURL depth ignores the base path")
    func basePathRelativeDepthUnchanged() {
        let root = SiteURLs(defaultLocale: "en")
        let mounted = SiteURLs(defaultLocale: "en", basePath: "/docs")
        // Same depth within the mounted site regardless of where it's served.
        #expect(root.baseURL(forLogicalPath: "index.md", locale: "en")
            == mounted.baseURL(forLogicalPath: "index.md", locale: "en"))
        #expect(root.baseURL(forLogicalPath: "install/macos.md", locale: "en")
            == mounted.baseURL(forLogicalPath: "install/macos.md", locale: "en"))
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
