/// Configuration for a blog: a collection of dated markdown posts that Kiln
/// renders as individual post pages plus generated listing pages (a paginated
/// index, per-tag pages) and an RSS feed.
///
/// A blog is **additive** to a ``KilnSite``: posts live in their own directory
/// and are discovered by scanning it, not via ``KilnSite/navigation``. The blog
/// index is the site root, so there is no `index.md`.
///
/// ```swift
/// let site = KilnSite(
///     name: "Vapor",
///     url: "https://blog.vapor.codes",
///     blog: Blog()
/// )
/// ```
///
/// - Note: A site with a blog must be single-language and unversioned (see
///   ``KilnSite/validate()``), which keeps generated URLs free of version and
///   locale prefixes.
public struct Blog: Sendable {
    /// Directory containing post markdown files, relative to the content
    /// directory (e.g. `"posts"`). Each `*.md` file becomes a post at
    /// `/posts/<filename>/`.
    public var postsDirectory: String
    /// Number of posts shown per page on the index and per-tag listings.
    public var postsPerPage: Int
    /// RSS channel title (defaults to the site name when `nil`).
    public var feedTitle: String?
    /// RSS channel description (defaults to the site description when `nil`).
    public var feedDescription: String?
    /// Heading/title for the blog index page (defaults to the site name when `nil`).
    public var indexTitle: String?
    /// Heading/title for the tags pages (defaults to `"Tags"` when `nil`).
    public var tagsTitle: String?
    /// `DateFormatter` format string used to parse each post's `date:`
    /// front-matter value. Parsing uses a fixed `en_US_POSIX` locale and UTC
    /// time zone so builds are reproducible across machines.
    public var dateFormat: String
    /// `DateFormatter` format string used to render a post's date for display
    /// (e.g. on the post page and cards).
    public var displayDateFormat: String
    /// Words-per-minute divisor for the estimated reading time.
    public var readingWordsPerMinute: Int
    /// The author registry. Posts reference an author by ``Author/username`` in
    /// front matter; unmatched authors fall back to a literal display name.
    public var authors: [Author]

    public init(
        postsDirectory: String = "posts",
        postsPerPage: Int = 8,
        feedTitle: String? = nil,
        feedDescription: String? = nil,
        indexTitle: String? = nil,
        tagsTitle: String? = nil,
        dateFormat: String = "yyyy-MM-dd HH:mm",
        displayDateFormat: String = "d MMMM yyyy",
        readingWordsPerMinute: Int = 200,
        authors: [Author] = []
    ) {
        self.postsDirectory = postsDirectory
        self.postsPerPage = postsPerPage
        self.feedTitle = feedTitle
        self.feedDescription = feedDescription
        self.indexTitle = indexTitle
        self.tagsTitle = tagsTitle
        self.dateFormat = dateFormat
        self.displayDateFormat = displayDateFormat
        self.readingWordsPerMinute = readingWordsPerMinute
        self.authors = authors
    }

    /// The author registry indexed by lower-cased username, for case-insensitive
    /// front-matter lookup (last entry wins on duplicate usernames).
    var authorsByUsername: [String: Author] {
        Dictionary(authors.map { ($0.username.lowercased(), $0) }, uniquingKeysWith: { _, latest in latest })
    }
}
