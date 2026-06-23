// Uses FileManager directory listing and DateFormatter, which live in full
// Foundation (not FoundationEssentials).
import Foundation

/// Loads the blog's posts from disk into a ``BlogCollection``.
///
/// Posts are the top-level `*.md` files in the blog's posts directory (the slug
/// is the filename — nested directories and locale suffixes are not used, since
/// a blog is single-language). Each post's body is rendered with the shared
/// ``MarkdownRenderer`` so it matches doc pages exactly.
struct BlogLoader {
    let contentDirectory: URL
    let blog: Blog
    let markdown: MarkdownRenderer
    let urls: SiteURLs
    let defaultLocale: String
    let knownLocales: Set<String>

    func load() -> BlogCollection {
        let postsURL = URL(fileURLWithPath: blog.postsDirectory, relativeTo: contentDirectory)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: postsURL.path) else {
            warn("posts directory not found: \(postsURL.path)")
            return BlogCollection(posts: [])
        }

        let parseFormatter = Self.formatter(format: blog.dateFormat)

        let files = (try? fileManager.contentsOfDirectory(
            at: postsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var posts: [BlogPost] = []
        for file in files where file.pathExtension.lowercased() == "md" {
            let slug = file.deletingPathExtension().lastPathComponent
            // A post named `index` would collapse onto the blog root URL.
            guard slug != "index" else {
                warn("ignoring post '\(file.lastPathComponent)': 'index' is reserved for the blog root")
                continue
            }

            let source = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let (frontMatter, body) = FrontMatter.parse(from: source)

            guard let rawDate = frontMatter.rawDate, !rawDate.isBlank else {
                warn("skipping post '\(slug)': missing 'date' front matter")
                continue
            }
            guard let date = parseFormatter.date(from: rawDate.trimmedWhitespace()) else {
                warn("skipping post '\(slug)': could not parse date '\(rawDate)' with format '\(blog.dateFormat)'")
                continue
            }

            // The post title is the leading `# H1`; strip it from the body so the
            // post page doesn't render it twice (mirrors Publish's bodyWithoutTitle).
            let (h1Title, bodyWithoutTitle) = Self.extractLeadingH1(body)

            let linkResolver = LinkResolver(
                currentLogicalPath: "posts/\(slug).md",
                locale: defaultLocale,
                urls: urls,
                knownLocales: knownLocales
            )
            let rendered = markdown.render(bodyWithoutTitle, linkResolver: linkResolver)

            let title = frontMatter.title ?? h1Title ?? rendered.firstHeading ?? slug
            let excerpt = frontMatter.description ?? rendered.metaDescription ?? ""
            let readingTime = Self.readingTime(html: rendered.html, wordsPerMinute: blog.readingWordsPerMinute)
            let authors = Self.authors(from: frontMatter, registry: blog.authorsByUsername)

            posts.append(BlogPost(
                slug: slug,
                title: title,
                date: date,
                rawDateString: rawDate,
                tags: frontMatter.tags,
                authors: authors,
                excerpt: excerpt,
                contentHTML: rendered.html,
                readingTimeMinutes: readingTime,
                socialImage: frontMatter.image,
                sourceURL: file,
                frontMatter: frontMatter
            ))
        }

        return BlogCollection(posts: posts)
    }

    /// Find a leading ATX `# ` heading (the post title) and return it along with
    /// the body that follows it. Blank lines before the heading are skipped; if
    /// the first non-blank line isn't a level-1 heading, the body is returned
    /// unchanged with a `nil` title.
    static func extractLeadingH1(_ body: String) -> (title: String?, body: String) {
        let lines = body.splitLines()
        guard let index = lines.firstIndex(where: { !$0.isBlank }) else {
            return (nil, body)
        }
        let line = lines[index].trimmedWhitespace()
        // A level-1 ATX heading: one `#`, a space, then the title (`## ` is h2).
        guard line.hasPrefix("# ") else { return (nil, body) }
        let title = String(line.dropFirst(2)).trimmedWhitespace()
        let remaining = lines[(index + 1)...].joined(separator: "\n")
        return (title.isEmpty ? nil : title, remaining)
    }

    /// Resolve a post's authors. Each front-matter token is looked up in the
    /// registry by username (case-insensitively); a match supplies the display
    /// name, avatar, profile URL and social profiles. An unmatched token falls
    /// back to a literal display name with its positional `authorImageURL`.
    static func authors(from frontMatter: FrontMatter, registry: [String: Author]) -> [BlogAuthor] {
        let tokens = frontMatter.authors
        let images = frontMatter.authorImageURLs
        return tokens.enumerated().map { index, token in
            if let author = registry[token.lowercased()] {
                return BlogAuthor(name: author.name, imageURL: author.imageURL, url: author.url, sameAs: author.sameAs)
            }
            let image = index < images.count ? images[index] : nil
            return BlogAuthor(name: token, imageURL: image)
        }
    }

    /// Estimated reading time in whole minutes (rounded up, at least 1).
    static func readingTime(html: String, wordsPerMinute: Int) -> Int {
        let words = SearchIndexBuilder.plainText(from: html)
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .count
        let perMinute = max(1, wordsPerMinute)
        return max(1, (words + perMinute - 1) / perMinute)
    }

    /// A `DateFormatter` pinned to `en_US_POSIX` + UTC so parsing/formatting is
    /// reproducible regardless of the build machine's locale and time zone.
    static func formatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    private func warn(_ message: String) {
        FileHandle.standardError.write(Data("[kiln] blog: \(message)\n".utf8))
    }
}
