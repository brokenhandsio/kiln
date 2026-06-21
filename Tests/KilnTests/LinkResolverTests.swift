import Testing
@testable import Kiln

@Suite("Link resolver")
struct LinkResolverTests {
    let urls = SiteURLs(defaultLocale: "en")

    func resolver(page: String, locale: String = "en") -> LinkResolver {
        LinkResolver(currentLogicalPath: page, locale: locale, urls: urls, knownLocales: ["en", "de", "es"])
    }

    @Test("Bare same-directory .md links resolve to pretty URLs")
    func sameDirectory() {
        let r = resolver(page: "basics/routing.md")
        #expect(r.resolve("content.md") == "/basics/content/")
    }

    @Test("Relative .md links with ../ resolve against the page directory")
    func parentRelative() {
        let r = resolver(page: "security/jwt.md")
        #expect(r.resolve("../advanced/sessions.md") == "/advanced/sessions/")
        #expect(r.resolve("../advanced/sessions.md#configuration") == "/advanced/sessions/#configuration")
    }

    @Test("Links to index resolve to the directory root")
    func indexLinks() {
        let r = resolver(page: "section/page.md")
        #expect(r.resolve("../index.md") == "/")
    }

    @Test("Locale-suffixed .md links resolve to that locale's URL")
    func localeSuffixedLinks() {
        let r = resolver(page: "security/authentication.de.md", locale: "de")
        // An explicit locale suffix is stripped and honoured.
        #expect(r.resolve("../basics/content.de.md") == "/de/basics/content/")
        // Cross-locale explicit links honour the named locale, not the page's.
        #expect(r.resolve("../basics/content.es.md") == "/es/basics/content/")
        // A non-locale middle segment is left intact (and keeps the page's locale).
        #expect(r.resolve("hello.world.md") == "/de/security/hello.world/")
    }

    @Test("Non-default locales are prefixed")
    func localePrefixed() {
        let r = resolver(page: "security/jwt.md", locale: "de")
        #expect(r.resolve("crypto.md") == "/de/security/crypto/")
        #expect(r.resolve("../index.md") == "/de/")
    }

    @Test("Relative asset links become root-absolute")
    func assets() {
        let r = resolver(page: "fluent/overview.md")
        #expect(r.resolve("../images/diagram.png") == "/images/diagram.png")
        #expect(r.resolve("images/local.png") == "/fluent/images/local.png")
    }

    @Test("A base path prefixes rewritten .md and asset links")
    func basePath() {
        let urls = SiteURLs(defaultLocale: "en", basePath: "/docs")
        let r = LinkResolver(currentLogicalPath: "fluent/overview.md", locale: "en", urls: urls,
                             knownLocales: ["en", "de"])
        #expect(r.resolve("crud.md") == "/docs/fluent/crud/")
        #expect(r.resolve("../images/diagram.png") == "/docs/images/diagram.png")
        // Author-written absolute links are still left untouched (documented limitation).
        #expect(r.resolve("/already/absolute/") == "/already/absolute/")
    }

    @Test("Absolute, external, anchor and mailto links are left untouched")
    func untouched() {
        let r = resolver(page: "basics/routing.md")
        #expect(r.resolve("https://github.com/vapor/vapor/blob/main/x.md") == "https://github.com/vapor/vapor/blob/main/x.md")
        #expect(r.resolve("/already/absolute/") == "/already/absolute/")
        #expect(r.resolve("#overview") == "#overview")
        #expect(r.resolve("mailto:team@vapor.codes") == "mailto:team@vapor.codes")
    }
}
