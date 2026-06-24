/// A custom labelled link for an author (rendered with a generic link icon).
public struct AuthorLink: Sendable {
    public var label: String
    public var url: String

    public init(label: String, url: String) {
        self.label = label
        self.url = url
    }
}

/// A resolved social link for an author: the URL, the icon class to render, and
/// an accessible label.
struct AuthorSocialLink: Sendable, Equatable {
    var url: String
    /// A `vapor-icon` class, e.g. `"icon-github-fill"`.
    var icon: String
    var label: String
}

/// A blog author in the site's author registry.
///
/// Posts reference an author by ``username`` in their `author:` / `authors:`
/// front matter (matched case-insensitively); Kiln resolves the rest — display
/// name, avatar, bio and social links — from this registry, generating an author
/// page (`/authors/<username>/`) and richer authorship metadata (a JSON-LD
/// `Person`). Socials are explicit, typed fields so each maps to a known icon
/// (rather than guessing from the URL host — important for federated networks).
///
/// A front-matter author not found in the registry falls back to being treated
/// as a literal display name (with the optional `authorImageURL`) and gets no
/// author page.
public struct Author: Sendable {
    /// The lookup key referenced from post front matter (case-insensitive); also
    /// the author-page slug.
    public var username: String
    /// Display name shown in bylines and used as the JSON-LD `Person` name.
    public var name: String
    /// Avatar image URL (e.g. `/author-images/tim.jpg`).
    public var imageURL: String?
    /// A short bio shown on the author page and the authors index.
    public var description: String?

    // Typed social profiles — each rendered with its platform icon.
    public var github: String?
    public var twitter: String?
    public var mastodon: String?
    public var bluesky: String?
    public var linkedin: String?
    public var instagram: String?
    /// A personal website (rendered with a generic link icon).
    public var website: String?
    /// Additional custom links (rendered with a generic link icon).
    public var links: [AuthorLink]

    public init(
        username: String,
        name: String,
        imageURL: String? = nil,
        description: String? = nil,
        github: String? = nil,
        twitter: String? = nil,
        mastodon: String? = nil,
        bluesky: String? = nil,
        linkedin: String? = nil,
        instagram: String? = nil,
        website: String? = nil,
        links: [AuthorLink] = []
    ) {
        self.username = username
        self.name = name
        self.imageURL = imageURL
        self.description = description
        self.github = github
        self.twitter = twitter
        self.mastodon = mastodon
        self.bluesky = bluesky
        self.linkedin = linkedin
        self.instagram = instagram
        self.website = website
        self.links = links
    }

    /// The `vapor-icon` class for `website` and custom links.
    static let genericLinkIcon = "icon-link-01"

    /// The author's social links in a stable order, each with its icon class and
    /// accessible label. Empty fields are skipped.
    var socialLinks: [AuthorSocialLink] {
        var result: [AuthorSocialLink] = []
        func add(_ url: String?, icon: String, label: String) {
            guard let url, !url.isBlank else { return }
            result.append(AuthorSocialLink(url: url, icon: icon, label: label))
        }
        add(github, icon: "icon-github-fill", label: "GitHub")
        add(twitter, icon: "icon-twitter-fill", label: "Twitter")
        add(mastodon, icon: "icon-mastodon-fill", label: "Mastodon")
        add(bluesky, icon: "icon-bsky-fill", label: "Bluesky")
        add(linkedin, icon: "icon-linkedin-fill", label: "LinkedIn")
        add(instagram, icon: "icon-instagram-fill", label: "Instagram")
        add(website, icon: Self.genericLinkIcon, label: "Website")
        for link in links where !link.url.isBlank {
            result.append(AuthorSocialLink(url: link.url, icon: Self.genericLinkIcon, label: link.label))
        }
        return result
    }
}
