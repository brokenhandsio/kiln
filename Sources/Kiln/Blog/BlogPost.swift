#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// One author of a blog post, resolved from the registry (or a literal
/// front-matter name): a display name, optional avatar, optional profile URL,
/// and any social profiles for structured-data authorship.
public struct BlogAuthor: Sendable, Equatable {
    public var name: String
    /// Avatar image URL (typically root-relative like `/author-images/tim.jpg`).
    public var imageURL: String?
    /// Profile URL — the byline links here, and it's the JSON-LD `Person.url`.
    public var url: String?
    /// Social/profile URLs for the JSON-LD `Person.sameAs`.
    public var sameAs: [String]

    public init(name: String, imageURL: String? = nil, url: String? = nil, sameAs: [String] = []) {
        self.name = name
        self.imageURL = imageURL
        self.url = url
        self.sameAs = sameAs
    }
}

/// A single rendered blog post, built from a markdown file in the blog's posts
/// directory.
public struct BlogPost: Sendable {
    /// The filename without extension (`vapor-next-steps`), used as the URL slug.
    public var slug: String
    /// The post title (front matter `title:`, else the first `# heading`, else the slug).
    public var title: String
    /// The publication date, parsed from front matter.
    public var date: Date
    /// The raw `date:` string as authored (kept for display fallback / debugging).
    public var rawDateString: String
    /// Tag display names, in authored order.
    public var tags: [String]
    /// Authors, positionally zipped from the `authors`/`author` and image URL fields.
    public var authors: [BlogAuthor]
    /// Short summary for cards and meta description (front matter `description:`,
    /// else the first-paragraph excerpt).
    public var excerpt: String
    /// The rendered HTML body.
    public var contentHTML: String
    /// Estimated reading time in whole minutes (at least 1).
    public var readingTimeMinutes: Int
    /// Optional social/OpenGraph image for this post (front matter `image:`).
    public var socialImage: String?
    /// The markdown file on disk.
    public var sourceURL: URL
    /// Parsed front matter.
    public var frontMatter: FrontMatter
    /// The logical path used with ``SiteURLs`` (`posts/<slug>.md`), so the post
    /// page reuses the existing pretty-URL machinery (`/posts/<slug>/`).
    public var logicalPath: String { "posts/\(slug).md" }

    public init(
        slug: String,
        title: String,
        date: Date,
        rawDateString: String,
        tags: [String],
        authors: [BlogAuthor],
        excerpt: String,
        contentHTML: String,
        readingTimeMinutes: Int,
        socialImage: String?,
        sourceURL: URL,
        frontMatter: FrontMatter
    ) {
        self.slug = slug
        self.title = title
        self.date = date
        self.rawDateString = rawDateString
        self.tags = tags
        self.authors = authors
        self.excerpt = excerpt
        self.contentHTML = contentHTML
        self.readingTimeMinutes = readingTimeMinutes
        self.socialImage = socialImage
        self.sourceURL = sourceURL
        self.frontMatter = frontMatter
    }
}

/// A tag with its URL slug and the number of posts carrying it.
public struct BlogTag: Sendable, Equatable {
    /// Display name (first-seen casing among posts sharing the slug).
    public var name: String
    /// URL slug (`async-await`), derived via ``Slugger``.
    public var slug: String
    /// Number of posts with this tag.
    public var count: Int

    public init(name: String, slug: String, count: Int) {
        self.name = name
        self.slug = slug
        self.count = count
    }
}
