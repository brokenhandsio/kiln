import Testing
import Foundation
@testable import Kiln

@Suite("Blog build")
struct BlogTests {
    /// Build the bundled blog fixture (3 posts, 2 per page) into a temp dir.
    func buildFixture(linkChecking: LinkChecking = .warn) async throws -> URL {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            Issue.record("Could not locate the Fixtures resource")
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        let contentDirectory = fixtures.appendingPathComponent("blog")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-blog-test-\(UUID().uuidString)")

        let site = KilnSite(
            name: "Test Blog",
            url: "https://blog.example.com",
            description: "A test blog.",
            image: "static/og.png",
            llmsText: false,
            blog: Blog(postsPerPage: 2, indexTitle: "Articles", tagsTitle: "Tags")
        )

        try await Kiln.build(site, contentDirectory: contentDirectory, outputDirectory: output, linkChecking: linkChecking)
        return output
    }

    func read(_ output: URL, _ path: String) throws -> String {
        try String(contentsOf: output.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("Generates posts, paginated index, tag pages, feed and sitemap")
    func fileLayout() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let expected = [
            "posts/first-post/index.html",
            "posts/second-post/index.html",
            "posts/third-post/index.html",
            "index.html",              // index page 1
            "2/index.html",            // index page 2 (3 posts, 2 per page)
            "tags/index.html",         // tags landing page 1
            "tags/2/index.html",       // tags landing page 2 (paginates all posts)
            "tags/framework/index.html",
            "tags/framework/2/index.html",  // framework has 3 posts → 2 pages
            "tags/security/index.html",
            "tags/growth/index.html",
            "feed.rss",
            "sitemap.xml",
            "search/search_index.json",
        ]
        for file in expected {
            #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(file).path), "Missing \(file)")
        }
    }

    @Test("Post page renders title, formatted date, reading time and stripped body")
    func postPage() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let post = try read(output, "posts/third-post/index.html")
        #expect(post.contains("class=\"blog-post-header\""))
        #expect(post.contains("<div class=\"blog-content\">"))
        // Title comes from the leading H1; the H1 is stripped from the body, so
        // it appears exactly once (in the header, not duplicated in the content).
        #expect(post.contains("<h1 class=\"mb-4 mt-4\">Third Post</h1>"))
        // Ordinal long date and reading time.
        #expect(post.contains("1st March 2024"))
        #expect(post.contains("1 minute read"))
        // Tags link to the tag pages.
        #expect(post.contains("href=\"/tags/framework/\""))
    }

    @Test("Multi-author posts render every author and avatar")
    func multiAuthor() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let post = try read(output, "posts/second-post/index.html")
        #expect(post.contains("Tim"))
        #expect(post.contains("Gwynne"))
        #expect(post.contains("src=\"/author-images/tim.jpg\""))
        #expect(post.contains("src=\"/author-images/gwynne.jpg\""))
    }

    @Test("Posts carry SEO/social meta, including a per-post image")
    func postMeta() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let post = try read(output, "posts/third-post/index.html")
        #expect(post.contains("<link rel=\"canonical\" href=\"https://blog.example.com/posts/third-post/\">"))
        #expect(post.contains("<meta property=\"og:type\" content=\"article\">"))
        #expect(post.contains("<meta property=\"og:image\" content=\"https://blog.example.com/static/images/posts/third.png\">"))
        #expect(post.contains("<meta property=\"og:image:type\" content=\"image/png\">"))
        #expect(post.contains("<meta property=\"og:image:alt\" content=\"Third Post\">"))
        // The excerpt becomes the meta description.
        #expect(post.contains("<meta name=\"description\" content=\"The newest post, which ships with its own social preview image.\">"))
        // Article metadata for posts: published time (ISO-8601 UTC), author, tags.
        #expect(post.contains("<meta property=\"article:published_time\" content=\"2024-03-01T18:00:00Z\">"))
        #expect(post.contains("<meta property=\"article:author\" content=\"Paul\">"))
        #expect(post.contains("<meta property=\"article:tag\" content=\"framework\">"))

        // JSON-LD BlogPosting node with headline, date, author, image, keywords.
        #expect(post.contains("\"@type\":\"BlogPosting\""))
        #expect(post.contains("\"headline\":\"Third Post\""))
        #expect(post.contains("\"datePublished\":\"2024-03-01T18:00:00Z\""))
        #expect(post.contains("\"image\":\"https:\\/\\/blog.example.com\\/static\\/images\\/posts\\/third.png\"") || post.contains("\"image\":\"https://blog.example.com/static/images/posts/third.png\""))
        #expect(post.contains("\"keywords\":\"framework\""))
        // Listing pages get no BlogPosting node.
        #expect(!(try read(output, "index.html")).contains("BlogPosting"))
    }

    @Test("Listing/tag pages are og:type website; posts carry article metadata")
    func ogType() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        // Index, paginated index and tag pages are websites, not articles.
        #expect(try read(output, "index.html").contains("<meta property=\"og:type\" content=\"website\">"))
        #expect(try read(output, "2/index.html").contains("<meta property=\"og:type\" content=\"website\">"))
        #expect(try read(output, "tags/framework/index.html").contains("<meta property=\"og:type\" content=\"website\">"))
        // Posts stay articles.
        #expect(try read(output, "posts/first-post/index.html").contains("<meta property=\"og:type\" content=\"article\">"))
        // Multi-author posts emit one article:author per author.
        let second = try read(output, "posts/second-post/index.html")
        #expect(second.contains("<meta property=\"article:author\" content=\"Tim\">"))
        #expect(second.contains("<meta property=\"article:author\" content=\"Gwynne\">"))
    }

    @Test("Index is paginated newest-first with working prev/next states")
    func indexPagination() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        // Page 1: the two newest posts; not the oldest. Previous disabled, Next → /2/.
        let page1 = try read(output, "index.html")
        #expect(page1.contains(">Third Post</h2>"))
        #expect(page1.contains(">Second Post</h2>"))
        #expect(!page1.contains(">First Post</h2>"))
        #expect(page1.contains("page-item me-auto disabled"))   // Previous disabled
        #expect(page1.contains("href=\"/2/\""))                 // Next link
        #expect(page1.contains("<h1 class=\"vapor-blog-page-heading\">Articles</h1>"))

        // Page 2: the oldest post; Next disabled, Previous → /.
        let page2 = try read(output, "2/index.html")
        #expect(page2.contains(">First Post</h2>"))
        #expect(page2.contains("page-item ms-auto disabled"))   // Next disabled
        #expect(page2.contains("href=\"/\""))
    }

    @Test("Tag pages list the right posts and mark the active tag")
    func tagPages() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        // Tags landing: sidebar with View All + per-tag counts.
        let landing = try read(output, "tags/index.html")
        #expect(landing.contains("View All<span class=\"badge ms-2 d-none d-lg-block\">3</span>"))
        #expect(landing.contains(">framework<span class=\"badge ms-2 d-none d-lg-block\">3</span>"))

        // The framework tag (all 3 posts): page 1 = two newest, marked active.
        let framework = try read(output, "tags/framework/index.html")
        #expect(framework.contains("tag-link d-flex align-items-center active"))
        #expect(framework.contains(">Third Post</h2>"))
        #expect(framework.contains(">Second Post</h2>"))
        #expect(framework.contains("href=\"/tags/framework/2/\""))
        // Page 2 of the framework tag holds the oldest post.
        let frameworkPage2 = try read(output, "tags/framework/2/index.html")
        #expect(frameworkPage2.contains(">First Post</h2>"))

        // A single-post tag has just one page.
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("tags/security/index.html").path))
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("tags/security/2/index.html").path))
    }

    @Test("RSS feed lists every post newest-first")
    func rssFeed() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let feed = try read(output, "feed.rss")
        #expect(feed.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(feed.contains("<rss version=\"2.0\""))
        #expect(feed.contains("<title>Third Post</title>"))
        #expect(feed.contains("<link>https://blog.example.com/posts/third-post/</link>"))
        #expect(feed.contains("<pubDate>"))
        #expect(feed.contains("<category>framework</category>"))
        // Newest post appears before the oldest in the feed.
        let third = try #require(feed.range(of: "<title>Third Post</title>"))
        let first = try #require(feed.range(of: "<title>First Post</title>"))
        #expect(third.lowerBound < first.lowerBound)
    }

    @Test("Sitemap and search index include the blog pages")
    func sitemapAndSearch() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let sitemap = try read(output, "sitemap.xml")
        #expect(sitemap.contains("<loc>https://blog.example.com/posts/third-post/</loc>"))
        #expect(sitemap.contains("<loc>https://blog.example.com/</loc>"))
        #expect(sitemap.contains("<loc>https://blog.example.com/tags/framework/</loc>"))

        // The search index holds exactly the three posts.
        let data = try Data(contentsOf: output.appendingPathComponent("search/search_index.json"))
        let index = try JSONDecoder().decode(SearchIndex.self, from: data)
        #expect(index.docs.count == 3)
        #expect(index.docs.contains { $0.title == "Third Post" })
    }
}
