import Testing
import Foundation
@testable import Kiln

@Suite("Blog units")
struct BlogUnitTests {
    // MARK: Front matter parsing

    @Test("Comma tags and single author parse")
    func singleAuthorFrontMatter() {
        let (fm, _) = FrontMatter.parse(from: """
        ---
        date: 2024-01-01 09:00
        tags: framework, growth, business
        author: Tim
        authorImageURL: /author-images/tim.jpg
        ---
        Body.
        """)
        #expect(fm.tags == ["framework", "growth", "business"])
        #expect(fm.authors == ["Tim"])
        #expect(fm.authorImageURLs == ["/author-images/tim.jpg"])
        #expect(fm.rawDate == "2024-01-01 09:00")
    }

    @Test("Semicolon multi-author parses and takes precedence over `author`")
    func multiAuthorFrontMatter() {
        let (fm, _) = FrontMatter.parse(from: """
        ---
        authors: Tim; Gwynne
        authorImageURLs: /author-images/tim.jpg; /author-images/gwynne.jpg
        author: Ignored
        ---
        Body.
        """)
        #expect(fm.authors == ["Tim", "Gwynne"])
        #expect(fm.authorImageURLs == ["/author-images/tim.jpg", "/author-images/gwynne.jpg"])
    }

    @Test("Missing author/tag fields yield empty arrays")
    func emptyFrontMatter() {
        let fm = FrontMatter.empty
        #expect(fm.tags.isEmpty)
        #expect(fm.authors.isEmpty)
        #expect(fm.authorImageURLs.isEmpty)
        #expect(fm.rawDate == nil)
    }

    // MARK: Author registry resolution

    @Test("Registered authors resolve from the registry; unknown ones fall back")
    func authorRegistryResolution() {
        let registry: [String: Author] = [
            "tim": Author(username: "tim", name: "Tim Condon", imageURL: "/r/tim.png",
                          github: "https://github.com/tim", website: "https://example.com/tim"),
        ]
        // Lookup is case-insensitive; a second, unknown author is positionally
        // paired with its front-matter image and kept as a literal name.
        let (fm, _) = FrontMatter.parse(from: """
        ---
        authors: Tim; Jane Doe
        authorImageURLs: /ignored.jpg; /jane.jpg
        ---
        Body.
        """)
        let authors = BlogLoader.authors(from: fm, registry: registry)
        #expect(authors.count == 2)
        // Registered: name/image/username from the registry; sameAs = all socials
        // (in socialLinks order: github, then website).
        #expect(authors[0] == BlogAuthor(name: "Tim Condon", imageURL: "/r/tim.png", username: "tim",
                                         sameAs: ["https://github.com/tim", "https://example.com/tim"]))
        // Unknown: literal name + positional image, no username/sameAs.
        #expect(authors[1] == BlogAuthor(name: "Jane Doe", imageURL: "/jane.jpg"))
    }

    @Test("Author.socialLinks orders typed fields and maps each to its icon")
    func authorSocialLinks() {
        let author = Author(
            username: "x", name: "X",
            github: "https://github.com/x", bluesky: "https://bsky.app/x",
            website: "https://x.dev",
            links: [AuthorLink(label: "Talks", url: "https://x.dev/talks")]
        )
        let links = author.socialLinks
        #expect(links.map(\.icon) == [
            "icon-github-fill", "icon-bsky-fill", "icon-link-01", "icon-link-01",
        ])
        #expect(links.map(\.label) == ["GitHub", "Bluesky", "Website", "Talks"])
        #expect(links.last?.url == "https://x.dev/talks")
    }

    // MARK: H1 extraction

    @Test("Leading H1 is extracted as the title and removed from the body")
    func extractLeadingH1() {
        let (title, body) = BlogLoader.extractLeadingH1("\n# The Title\n\nSome body text.")
        #expect(title == "The Title")
        #expect(!body.contains("# The Title"))
        #expect(body.contains("Some body text."))
    }

    @Test("A body without a leading H1 is returned unchanged")
    func noLeadingH1() {
        let (title, body) = BlogLoader.extractLeadingH1("Just a paragraph.\n\n## A subheading")
        #expect(title == nil)
        #expect(body == "Just a paragraph.\n\n## A subheading")
    }

    // MARK: Reading time

    @Test("Reading time rounds up and is at least one minute")
    func readingTime() {
        #expect(BlogLoader.readingTime(html: "<p>one two three</p>", wordsPerMinute: 200) == 1)
        let longBody = "<p>" + String(repeating: "word ", count: 450) + "</p>"
        #expect(BlogLoader.readingTime(html: longBody, wordsPerMinute: 200) == 3) // ceil(450/200)
    }

    // MARK: Collection sorting & tags

    private func post(_ slug: String, _ date: String, tags: [String]) -> BlogPost {
        let formatter = BlogLoader.formatter(format: "yyyy-MM-dd")
        return BlogPost(
            slug: slug, title: slug, date: formatter.date(from: date)!, rawDateString: date,
            tags: tags, authors: [], excerpt: "", contentHTML: "", readingTimeMinutes: 1,
            socialImage: nil, sourceURL: URL(fileURLWithPath: "/\(slug).md"), frontMatter: .empty
        )
    }

    @Test("Posts sort newest-first; tags aggregate counts case-insensitively")
    func collection() {
        let collection = BlogCollection(posts: [
            post("a", "2024-01-01", tags: ["Framework", "Growth"]),
            post("c", "2024-03-01", tags: ["framework"]),
            post("b", "2024-02-01", tags: ["Framework", "Security"]),
        ])

        // Newest first.
        #expect(collection.posts.map(\.slug) == ["c", "b", "a"])

        // `Framework` and `framework` collapse to one tag with three posts.
        let framework = collection.tags.first { $0.slug == "framework" }
        #expect(framework?.count == 3)
        // First-seen casing after the newest-first sort: post "c" uses lowercase.
        #expect(framework?.name == "framework")
        // Sorted by count desc: framework (3) before growth/security (1 each).
        #expect(collection.tags.first?.slug == "framework")

        // Tag lookup preserves newest-first order.
        #expect(collection.posts(taggedSlug: "framework").map(\.slug) == ["c", "b", "a"])
        #expect(collection.posts(taggedSlug: "security").map(\.slug) == ["b"])
    }

    // MARK: Pagination windowing

    @Test("Few pages show in full")
    func paginationSmall() {
        #expect(BlogLeafData.visiblePages(current: 1, total: 1) == [1])
        #expect(BlogLeafData.visiblePages(current: 2, total: 5).compactMap { $0 } == [1, 2, 3, 4, 5])
    }

    @Test("Many pages collapse with an ellipsis around the active page")
    func paginationWindowed() {
        let pages = BlogLeafData.visiblePages(current: 8, total: 15)
        // First three, the active page ±1, and the last three, with ellipsis gaps.
        #expect(pages.contains(nil))                          // has at least one ellipsis
        #expect(pages.compactMap { $0 }.contains(1))
        #expect(pages.compactMap { $0 }.contains(8))          // active
        #expect(pages.compactMap { $0 }.contains(15))         // last
        #expect(!pages.compactMap { $0 }.contains(6))         // collapsed away
    }
}
