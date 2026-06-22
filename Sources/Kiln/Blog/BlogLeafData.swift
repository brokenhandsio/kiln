import LeafKit

/// Builds the `blogPost.*` and `blogListing.*` template data injected into
/// ``RenderContext`` for blog pages. Keeping the shaping here means
/// ``RenderContext`` only carries two opaque optional `LeafData` values, so no
/// existing (non-blog) page is affected.
enum BlogLeafData {
    // MARK: Post page

    /// `blogPost.*` data for a single post page.
    static func post(_ post: BlogPost, urls: SiteURLs, blog: Blog) -> LeafData {
        .dictionary([
            "title": .string(post.title),
            "description": .string(post.excerpt),
            "hasDescription": .bool(!post.excerpt.isEmpty),
            "formattedDate": .string(BlogDateFormatting.long(post.date)),
            "formattedDateShort": .string(BlogDateFormatting.short(post.date, format: blog.displayDateFormat)),
            "isoDate": .string(BlogDateFormatting.iso(post.date)),
            "readingTime": .int(post.readingTimeMinutes),
            "readingTimeText": .string(readingTimeText(post.readingTimeMinutes)),
            "content": .string(post.contentHTML),
            "authors": authorsData(post.authors),
            "hasAuthors": .bool(!post.authors.isEmpty),
            "tags": tagRefsData(post.tags, urls: urls),
            "hasTags": .bool(!post.tags.isEmpty),
            "url": .string(urls.urlPath(forLogicalPath: post.logicalPath, locale: urls.defaultLocale)),
            "feedURL": .string(urls.feedURLPath()),
            "socialImage": .string(post.socialImage),
            "hasSocialImage": .bool(post.socialImage != nil),
        ])
    }

    // MARK: Listing pages (index + tags)

    /// `blogListing.*` data for an index or tag page.
    static func listing(
        heading: String,
        cards: [BlogPost],
        currentPage: Int,
        totalPages: Int,
        urlForPage: (Int) -> String,
        tags: [BlogTag],
        activeTagSlug: String?,
        isTagsPage: Bool,
        totalPostCount: Int,
        urls: SiteURLs,
        blog: Blog
    ) -> LeafData {
        var dict: [String: LeafData] = [
            "heading": .string(heading),
            "isTagsPage": .bool(isTagsPage),
            "posts": .array(cards.map { card($0, urls: urls, blog: blog) }),
            "hasPosts": .bool(!cards.isEmpty),
            "hasTags": .bool(!tags.isEmpty),
            "pagination": pagination(current: currentPage, total: totalPages, urlForPage: urlForPage),
            "tags": tagListData(tags, activeTagSlug: activeTagSlug, urls: urls),
            "tagsIndexURL": .string(urls.blogTagsURLPath(page: 1)),
            "indexURL": .string(urls.blogIndexURLPath(page: 1)),
            "feedURL": .string(urls.feedURLPath()),
            "totalPostCount": .int(totalPostCount),
            // "View All" is active on the tags landing page (no specific tag).
            "allActive": .bool(isTagsPage && activeTagSlug == nil),
        ]
        if let activeTagSlug, let active = tags.first(where: { $0.slug == activeTagSlug }) {
            dict["activeTagName"] = .string(active.name)
            dict["activeTagSlug"] = .string(active.slug)
        }
        return .dictionary(dict)
    }

    // MARK: Components

    private static func card(_ post: BlogPost, urls: SiteURLs, blog: Blog) -> LeafData {
        .dictionary([
            "title": .string(post.title),
            "url": .string(urls.urlPath(forLogicalPath: post.logicalPath, locale: urls.defaultLocale)),
            "formattedDate": .string(BlogDateFormatting.short(post.date, format: blog.displayDateFormat)),
            "formattedDateLong": .string(BlogDateFormatting.long(post.date)),
            "isoDate": .string(BlogDateFormatting.iso(post.date)),
            "excerpt": .string(post.excerpt),
            "readingTime": .int(post.readingTimeMinutes),
            "readingTimeText": .string(readingTimeText(post.readingTimeMinutes)),
            "authors": authorsData(post.authors),
            "authorNames": .string(post.authors.map(\.name).joined(separator: ", ")),
            "hasAuthors": .bool(!post.authors.isEmpty),
            "tags": tagRefsData(post.tags, urls: urls),
            "hasTags": .bool(!post.tags.isEmpty),
            "socialImage": .string(post.socialImage),
            "hasSocialImage": .bool(post.socialImage != nil),
        ])
    }

    private static func authorsData(_ authors: [BlogAuthor]) -> LeafData {
        .array(authors.map { author in
            .dictionary([
                "name": .string(author.name),
                "imageURL": .string(author.imageURL),
                "hasImage": .bool(author.imageURL != nil),
            ])
        })
    }

    /// Tag pills carried on a post/card: name, slug and link to the tag page.
    private static func tagRefsData(_ tags: [String], urls: SiteURLs) -> LeafData {
        .array(tags.map { tag in
            let slug = Slugger.normalise(tag)
            return .dictionary([
                "name": .string(tag),
                "slug": .string(slug),
                "url": .string(urls.blogTagURLPath(slug: slug, page: 1)),
            ])
        })
    }

    /// The tag sidebar list: every tag with its post count and active state.
    private static func tagListData(_ tags: [BlogTag], activeTagSlug: String?, urls: SiteURLs) -> LeafData {
        .array(tags.map { tag in
            .dictionary([
                "name": .string(tag.name),
                "slug": .string(tag.slug),
                "url": .string(urls.blogTagURLPath(slug: tag.slug, page: 1)),
                "count": .int(tag.count),
                "isActive": .bool(tag.slug == activeTagSlug),
            ])
        })
    }

    private static func pagination(current: Int, total: Int, urlForPage: (Int) -> String) -> LeafData {
        var dict: [String: LeafData] = [
            "currentPage": .int(current),
            "totalPages": .int(total),
            "hasMultiplePages": .bool(total > 1),
            "hasPrevious": .bool(current > 1),
            "hasNext": .bool(current < total),
            "prevURL": .string(current > 1 ? urlForPage(current - 1) : nil),
            "nextURL": .string(current < total ? urlForPage(current + 1) : nil),
        ]
        let links = visiblePages(current: current, total: total).map { page -> LeafData in
            guard let page else {
                return .dictionary([
                    "page": .int(0),
                    "url": .string(nil),
                    "isCurrent": .bool(false),
                    "isEllipsis": .bool(true),
                ])
            }
            return .dictionary([
                "page": .int(page),
                "url": .string(urlForPage(page)),
                "isCurrent": .bool(page == current),
                "isEllipsis": .bool(false),
            ])
        }
        dict["links"] = .array(links)
        return .dictionary(dict)
    }

    /// Page numbers to show in the pagination control; `nil` marks an ellipsis
    /// gap. Up to 9 pages show in full; beyond that, the first three, last three
    /// and the active page ±1 are shown, matching the previous blog's behaviour.
    static func visiblePages(current: Int, total: Int) -> [Int?] {
        guard total > 1 else { return total == 1 ? [1] : [] }
        if total <= 9 { return Array(1...total).map { Optional($0) } }

        var keep = Set<Int>()
        for page in [1, 2, 3, total - 2, total - 1, total, current - 1, current, current + 1] where page >= 1 && page <= total {
            keep.insert(page)
        }

        var result: [Int?] = []
        var previous = 0
        for page in keep.sorted() {
            if page - previous > 1 { result.append(nil) }   // a gap → one ellipsis
            result.append(page)
            previous = page
        }
        return result
    }

    private static func readingTimeText(_ minutes: Int) -> String {
        minutes == 1 ? "1 minute read" : "\(minutes) minutes read"
    }
}
