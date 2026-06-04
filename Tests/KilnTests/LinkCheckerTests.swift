import Testing
@testable import Kiln

@Suite("Link checker")
struct LinkCheckerTests {
    // A small site: three built pages, with known headings and one existing asset.
    let checker = LinkChecker(
        builtPages: ["index.md", "basics/routing.md", "basics/content.md"],
        slugs: [
            "index.md": ["en": ["welcome", "section-one"]],
            "basics/routing.md": ["en": ["overview", "http-method"]],
        ],
        defaultLocale: "en",
        knownLocales: ["en", "de", "es"],
        // Resolved (content-relative) asset paths that exist.
        assetExists: { $0 == "basics/images/ok.png" || $0 == "basics/diagram.png" }
    )

    func issues(_ links: [String], images: [String] = []) -> [LinkIssue] {
        checker.issues(forPage: "basics/routing.md", locale: "en",
                       sourcePath: "basics/routing.md", links: links, images: images)
    }

    @Test("Valid internal links, anchors and externals produce no issues")
    func valid() {
        let found = issues([
            "content.md",                 // → basics/content.md (built)
            "../index.md",                // → index.md (built)
            "../index.md#section-one",    // valid cross-page anchor
            "#overview",                  // valid same-page anchor
            "https://example.com",        // external — skipped
            "mailto:team@vapor.codes",    // skipped
            "/already/absolute/",         // root-absolute — skipped
        ], images: ["images/ok.png", "../basics/diagram.png"])
        #expect(found.isEmpty)
    }

    @Test("Locale-suffixed links validate against the logical page")
    func localeSuffixedLinks() {
        // `content.de.md` → logical basics/content.md (built) → valid.
        #expect(issues(["content.de.md"]).isEmpty)
        // A locale-suffixed link to a page that isn't built is still reported,
        // by its logical path.
        #expect(issues(["typo.es.md"]).first?.kind == .missingPage(target: "basics/typo.md"))
    }

    @Test("A link to a non-built page is reported")
    func missingPage() {
        let found = issues(["typo.md"])
        #expect(found.count == 1)
        #expect(found.first?.kind == .missingPage(target: "basics/typo.md"))
    }

    @Test("A bad same-page anchor is reported")
    func missingSamePageAnchor() {
        let found = issues(["#does-not-exist"])
        #expect(found.first?.kind == .missingAnchor(target: "basics/routing.md", fragment: "does-not-exist"))
    }

    @Test("A bad cross-page anchor is reported")
    func missingCrossPageAnchor() {
        let found = issues(["../index.md#nope"])
        #expect(found.first?.kind == .missingAnchor(target: "index.md", fragment: "nope"))
    }

    @Test("A missing relative asset/image is reported")
    func missingAsset() {
        let linkIssues = issues(["data.csv"])
        #expect(linkIssues.first?.kind == .missingAsset(path: "basics/data.csv"))

        let imageIssues = issues([], images: ["images/missing.png"])
        #expect(imageIssues.first?.kind == .missingAsset(path: "basics/images/missing.png"))
    }
}
