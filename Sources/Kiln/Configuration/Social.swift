/// A social/external link rendered in the site footer.
public struct SocialLink: Sendable {
    public var icon: SocialIcon
    public var link: String

    public init(icon: SocialIcon, link: String) {
        self.icon = icon
        self.link = link
    }
}

/// Known social icons. The default theme ships inline SVGs for these; use
/// `.custom` to reference an icon name your own theme provides.
@nonexhaustive
public enum SocialIcon: Sendable, Equatable {
    case twitter
    case mastodon
    case github
    case discord
    case linkedin
    case youtube
    case rss
    case custom(String)

    /// Stable identifier used by the theme to pick an icon.
    public var name: String {
        switch self {
        case .twitter: return "twitter"
        case .mastodon: return "mastodon"
        case .github: return "github"
        case .discord: return "discord"
        case .linkedin: return "linkedin"
        case .youtube: return "youtube"
        case .rss: return "rss"
        case .custom(let name): return name
        }
    }
}
