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
            blog: Blog(
                postsPerPage: 2, indexTitle: "Articles", tagsTitle: "Tags",
                // Registry images/urls differ from the posts' front matter, so a
                // resolved author proves the username lookup (not the fallback).
                authors: [
                    .init(username: "tim", name: "Tim", imageURL: "/registry/tim.png",
                          description: "Core team member.",
                          github: "https://github.com/tim-example", website: "https://example.com/tim"),
                    .init(username: "gwynne", name: "Gwynne", imageURL: "/registry/gwynne.png"),
                    .init(username: "paul", name: "Paul", imageURL: "/registry/paul.png",
                          website: "https://example.com/paul"),
                    // A registry author with no posts still gets an (empty) page.
                    .init(username: "ghost", name: "Ghost"),
                ]
            )
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
            "tags/index.html",         // tag directory
            "tags/framework/index.html",
            "tags/framework/2/index.html",  // framework has 3 posts → 2 pages
            "tags/security/index.html",
            "tags/growth/index.html",
            "authors/index.html",          // authors index
            "authors/tim/index.html",      // per-author page
            "authors/gwynne/index.html",
            "authors/paul/index.html",
            "authors/ghost/index.html",    // author with no posts
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
        // Avatars resolve from the registry (proving the username lookup), not the
        // posts' own `authorImageURLs`.
        #expect(post.contains("src=\"/registry/tim.png\""))
        #expect(post.contains("src=\"/registry/gwynne.png\""))
    }

    @Test("Authors resolve from the registry: byline links to the author page + Person JSON-LD")
    func authorRegistry() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        // third-post `author: Paul` — avatar from the registry; the byline name
        // links to the author PAGE (not the external website).
        let post = try read(output, "posts/third-post/index.html")
        #expect(post.contains("src=\"/registry/paul.png\""))
        #expect(post.contains("<a href=\"/authors/paul/\" rel=\"author\">Paul</a>"))
        // JSON-LD Person.url = the on-site author page; sameAs = external profiles.
        #expect(post.contains("\"@type\":\"Person\""))
        #expect(post.contains("\"url\":\"https://blog.example.com/authors/paul/\""))
        #expect(post.contains("\"sameAs\":[\"https://example.com/paul\"]"))

        // Multi-author post: Tim's Person carries both github + website in sameAs.
        let second = try read(output, "posts/second-post/index.html")
        #expect(second.contains("\"url\":\"https://blog.example.com/authors/tim/\""))
        #expect(second.contains("\"sameAs\":[\"https://github.com/tim-example\",\"https://example.com/tim\"]"))
    }

    @Test("Authors index lists all authors; author pages paginate their posts")
    func authorPages() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        // Authors index: a card per registry author, linking to the author page.
        let index = try read(output, "authors/index.html")
        #expect(index.contains("<h1 class=\"main-title\">Authors</h1>"))
        #expect(index.contains("href=\"/authors/tim/\""))
        #expect(index.contains("href=\"/authors/gwynne/\""))
        #expect(index.contains("href=\"/authors/paul/\""))
        // Tim's card shows his bio + social icons (github + website).
        #expect(index.contains("Core team member."))
        #expect(index.contains("vapor-icon icon-github-fill"))
        #expect(index.contains("vapor-icon icon-link-01"))   // website → generic link

        // Tim's author page: header + his posts. Tim wrote second-post (only).
        let tim = try read(output, "authors/tim/index.html")
        #expect(tim.contains("<h1 class=\"main-title\">Tim</h1>"))
        #expect(tim.contains("@tim"))
        #expect(tim.contains(">Second Post</h2>"))
        #expect(!tim.contains(">Third Post</h2>"))   // Third Post is Paul's

        // Author page JSON-LD: a ProfilePage whose mainEntity is the author Person.
        #expect(tim.contains("\"@type\":\"ProfilePage\""))
        #expect(tim.contains("\"@type\":\"Person\""))
        #expect(tim.contains("\"@id\":\"https://blog.example.com/authors/tim/#person\""))
        #expect(tim.contains("\"mainEntity\":{\"@id\":\"https://blog.example.com/authors/tim/#person\"}"))
        #expect(tim.contains("\"description\":\"Core team member.\""))
        #expect(tim.contains("\"sameAs\":[\"https://github.com/tim-example\",\"https://example.com/tim\"]"))

        // The social card uses the default site OG image (a square avatar would be
        // cropped in a summary_large_image card) — but the Person image stays the avatar.
        #expect(tim.contains("<meta property=\"og:image\" content=\"https://blog.example.com/static/og.png\">"))
        #expect(tim.contains("<meta name=\"twitter:image\" content=\"https://blog.example.com/static/og.png\">"))
        #expect(!tim.contains("<meta property=\"og:image\" content=\"https://blog.example.com/registry/tim.png\">"))
        #expect(tim.contains("\"image\":\"https://blog.example.com/registry/tim.png\""))

        // A registry author with no posts still gets an (empty) page and an index card.
        #expect(index.contains("href=\"/authors/ghost/\""))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("authors/ghost/index.html").path))
        let ghost = try read(output, "authors/ghost/index.html")
        #expect(ghost.contains("<h1 class=\"main-title\">Ghost</h1>"))
        #expect(!ghost.contains("class=\"card blog-card\""))   // no posts
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
        #expect(post.contains("\"image\":\"https://blog.example.com/static/images/posts/third.png\""))
        #expect(post.contains("\"keywords\":\"framework\""))
        // A BreadcrumbList trail (Home › post) for breadcrumb rich results.
        #expect(post.contains("\"@type\":\"BreadcrumbList\""))
        #expect(post.contains("\"name\":\"Third Post\""))
        // Listing pages get no BlogPosting node.
        #expect(!(try read(output, "index.html")).contains("BlogPosting"))
    }

    @Test("Sitemap carries <lastmod> from post dates")
    func sitemapLastmod() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        let sitemap = try read(output, "sitemap.xml")
        // Each post's <loc> carries its publication date as <lastmod>.
        #expect(sitemap.contains("<loc>https://blog.example.com/posts/third-post/</loc><lastmod>2024-03-01</lastmod>"))
        #expect(sitemap.contains("<loc>https://blog.example.com/posts/first-post/</loc><lastmod>2024-01-01</lastmod>"))
        // Listing pages are dated to the newest post.
        #expect(sitemap.contains("<loc>https://blog.example.com/</loc><lastmod>2024-03-01</lastmod>"))
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

    @Test("Tag directory lists tags with counts; per-tag pages hold the posts")
    func tagPages() async throws {
        let output = try await buildFixture()
        defer { try? FileManager.default.removeItem(at: output) }

        // The tag directory: each tag linked with its post count, and NO post feed
        // (so it doesn't duplicate the index). It isn't paginated.
        let directory = try read(output, "tags/index.html")
        #expect(directory.contains("<h1 class=\"vapor-blog-page-heading\">Tags</h1>"))
        #expect(directory.contains("href=\"/tags/framework/\">framework (3)</a>"))
        #expect(directory.contains("href=\"/tags/security/\">security (1)</a>"))
        #expect(!directory.contains(">Third Post</h2>"))   // no post feed here
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("tags/2/index.html").path))

        // The framework tag (all 3 posts): tag-specific heading; page 1 = two
        // newest, active in the sidebar; oldest on page 2.
        let framework = try read(output, "tags/framework/index.html")
        #expect(framework.contains("Posts tagged framework"))
        #expect(framework.contains("tag-link d-flex align-items-center active"))
        #expect(framework.contains(">Third Post</h2>"))
        #expect(framework.contains(">Second Post</h2>"))
        #expect(framework.contains("href=\"/tags/framework/2/\""))
        #expect(try read(output, "tags/framework/2/index.html").contains(">First Post</h2>"))

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

        // The feed carries the full post body via `content:encoded` (not just the
        // excerpt), and root-relative links are absolutised so they resolve in a
        // reader. Second Post's body links to the security tag with a `/…` URL.
        #expect(feed.contains("xmlns:content=\"http://purl.org/rss/1.0/modules/content/\""))
        #expect(feed.contains("<content:encoded>"))
        #expect(feed.contains("https://blog.example.com/tags/security/"))
        #expect(!feed.contains("href=\"/"))   // no root-relative links leak into the feed
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
