/// The full set of blog posts, sorted newest-first, with tags aggregated across
/// them. Built once per build by ``BlogLoader``.
public struct BlogCollection: Sendable {
    /// Every post, sorted by date descending (newest first).
    public let posts: [BlogPost]
    /// Distinct tags, sorted by post count descending then name ascending.
    public let tags: [BlogTag]

    init(posts: [BlogPost]) {
        self.posts = posts.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            // Stable tie-break so equal-dated posts have a deterministic order.
            return lhs.slug < rhs.slug
        }
        self.tags = Self.aggregateTags(from: self.posts)
    }

    /// Posts carrying the tag with the given slug, preserving the newest-first order.
    public func posts(taggedSlug slug: String) -> [BlogPost] {
        posts.filter { post in
            post.tags.contains { Slugger.normalise($0) == slug }
        }
    }

    /// Group the posts' tags by slug (case-insensitively), counting posts and
    /// keeping the first-seen display name for each slug.
    private static func aggregateTags(from posts: [BlogPost]) -> [BlogTag] {
        var order: [String] = []                  // slugs in first-seen order
        var names: [String: String] = [:]         // slug -> display name
        var counts: [String: Int] = [:]           // slug -> post count

        for post in posts {
            // A post counts once per distinct tag-slug it carries.
            var seenInPost: Set<String> = []
            for tag in post.tags {
                let slug = Slugger.normalise(tag)
                guard !slug.isEmpty, seenInPost.insert(slug).inserted else { continue }
                if names[slug] == nil {
                    names[slug] = tag
                    order.append(slug)
                }
                counts[slug, default: 0] += 1
            }
        }

        return order
            .map { BlogTag(name: names[$0] ?? $0, slug: $0, count: counts[$0] ?? 0) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.lowercased() < rhs.name.lowercased()
            }
    }
}
