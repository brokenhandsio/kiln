import Testing
@testable import Kiln

@Suite("Link checker")
struct LinkCheckerTests {
    // A small site: three built pages, with known headings and one existing asset.
    let checker = LinkChecker(
        builtPages: ["index.md", "basics/routing.md", "basics/content.md"],
        slugs: [
            "index.md": ["en": ["welcome", "section-one"], "es": ["bienvenido", "seccion-uno"]],
            "basics/routing.md": ["en": ["overview", "http-method"]],
        ],
        defaultLocale: "en",
        knownLocales: ["en", "de", "es"],
        // Resolved (content-relative) asset paths that exist.
        assetExists: { $0 == "basics/images/ok.png" || $0 == "basics/diagram.png" }
    )

    func issues(_ links: [String], images: [String] = [], locale: String = "en", isFallback: Bool = false) -> [LinkIssue] {
        checker.issues(forPage: "basics/routing.md", locale: locale,
                       sourcePath: "basics/routing.md", isFallback: isFallback, links: links, images: images)
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

    @Test("Cross-page anchors validate against the target in the source locale")
    func crossPageAnchorLocale() {
        // A Spanish page linking to the target's Spanish anchor passes (the old
        // checker wrongly validated against the default-language headings).
        #expect(issues(["../index.md#seccion-uno"], locale: "es").isEmpty)
        // The stale English anchor is correctly flagged on the Spanish page.
        #expect(issues(["../index.md#section-one"], locale: "es").first?.kind
                == .missingAnchor(target: "index.md", fragment: "section-one"))
        // A fallback page carries the default content's (English) anchors, so it's
        // validated against the default target — no unactionable noise.
        #expect(issues(["../index.md#section-one"], locale: "es", isFallback: true).isEmpty)
    }

    @Test("Directory-style (pretty URL) page links are recognised, not treated as assets")
    func directoryStylePageLinks() {
        // `../index/` and `../index` map to the built index.md page (MkDocs-style links).
        #expect(issues(["../index/"]).isEmpty)
        #expect(issues(["../index"]).isEmpty)
        // A valid anchor on a directory-style page link passes.
        #expect(issues(["../index/#section-one"]).isEmpty)
        // A bad anchor on one is still caught (as a missing anchor, not a missing file).
        #expect(issues(["../index/#nope"]).first?.kind == .missingAnchor(target: "index.md", fragment: "nope"))
        // A directory-style link to a non-page is still an asset miss.
        #expect(issues(["../nope/"]).first?.kind == .missingAsset(path: "nope"))
    }

    @Test("A missing relative asset/image is reported")
    func missingAsset() {
        let linkIssues = issues(["data.csv"])
        #expect(linkIssues.first?.kind == .missingAsset(path: "basics/data.csv"))

        let imageIssues = issues([], images: ["images/missing.png"])
        #expect(imageIssues.first?.kind == .missingAsset(path: "basics/images/missing.png"))
    }
}
