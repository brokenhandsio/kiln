/// A blog author in the site's author registry.
///
/// Posts reference an author by ``username`` in their `author:` / `authors:`
/// front matter (matched case-insensitively); Kiln resolves the rest — display
/// name, avatar, profile and social links — from this registry, so author
/// details live in one place and feed richer authorship metadata (a JSON-LD
/// `Person` with `url`/`sameAs`, and a linked byline).
///
/// A front-matter author not found in the registry falls back to being treated
/// as a literal display name (with the optional `authorImageURL`).
public struct Author: Sendable {
    /// The lookup key referenced from post front matter (case-insensitive).
    public var username: String
    /// Display name shown in bylines and used as the JSON-LD `Person` name.
    public var name: String
    /// Avatar image URL (e.g. `/author-images/tim.jpg`).
    public var imageURL: String?
    /// Profile URL — the byline links here, and it becomes the JSON-LD `Person.url`.
    public var url: String?
    /// Social/profile URLs for the JSON-LD `Person.sameAs` (authorship signals).
    public var sameAs: [String]

    public init(
        username: String,
        name: String,
        imageURL: String? = nil,
        url: String? = nil,
        sameAs: [String] = []
    ) {
        self.username = username
        self.name = name
        self.imageURL = imageURL
        self.url = url
        self.sameAs = sameAs
    }
}
