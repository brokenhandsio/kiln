import Testing
@testable import Kiln

@Suite("Navigation")
struct NavigationTests {
    let urls = SiteURLs(defaultLocale: "en")

    var navigation: [NavItem] {
        [
            Page("Welcome", "index.md"),
            Section("Guides") {
                Page("First", "guides/first.md")
                Page("Second", "guides/second.md")
            },
        ]
    }

    @Test("URLs are locale-prefixed for non-default languages")
    func localePrefixedURLs() {
        let builder = NavigationBuilder(urls: urls)
        let german = Language(.german)
        let resolved = builder.build(navigation, for: german)
        let firstGuide = resolved.orderedPages.first { $0.logicalPath == "guides/first.md" }
        #expect(firstGuide?.url == "/de/guides/first/")
    }

    @Test("Navigation titles are translated")
    func translatedTitles() {
        let builder = NavigationBuilder(urls: urls)
        let german = Language(.german, navTranslations: ["Guides": "Anleitungen"])
        let resolved = builder.build(navigation, for: german)
        let section = resolved.nodes.first { $0.kind == .section }
        #expect(section?.title == "Anleitungen")
    }

    @Test("Active trail and current page are marked")
    func activeTrail() {
        let builder = NavigationBuilder(urls: urls)
        let english = Language(.english, isDefault: true)
        let resolved = builder.build(navigation, for: english)
        let page = builder.contextualise(resolved, currentLogicalPath: "guides/second.md")

        let section = page.nodes.first { $0.kind == .section }
        #expect(section?.isActive == true)
        let current = section?.items.first { $0.logicalPath == "guides/second.md" }
        #expect(current?.isCurrent == true)
    }

    @Test("Previous and next links follow document order")
    func previousNext() {
        let builder = NavigationBuilder(urls: urls)
        let english = Language(.english, isDefault: true)
        let resolved = builder.build(navigation, for: english)
        let page = builder.contextualise(resolved, currentLogicalPath: "guides/first.md")
        #expect(page.previous?.logicalPath == "index.md")
        #expect(page.next?.logicalPath == "guides/second.md")
    }
}
