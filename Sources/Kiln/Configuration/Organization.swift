/// Publisher identity for JSON-LD structured data (the schema.org `Organization`
/// node), emitted on every page alongside a `WebSite` node. It establishes the
/// brand entity for search engines and AI agents — name, logo, and the social
/// profiles that represent it.
public struct Organization: Sendable {
    /// Organization name, e.g. `"Vapor"`. Falls back to ``KilnSite/name``.
    public var name: String?
    /// Canonical organization URL, e.g. `"https://www.vapor.codes"`. Falls back to
    /// ``KilnSite/url``. Set the same value across related sites (e.g. a docs
    /// subdomain) so they all reference one shared entity.
    public var url: String?
    /// Absolute URL of the organization logo (raster, ideally ≥112×112).
    public var logo: String?
    /// Profile URLs that represent the same entity (Twitter/Mastodon/GitHub/…),
    /// emitted as schema.org `sameAs`.
    public var sameAs: [String]

    public init(name: String? = nil, url: String? = nil, logo: String? = nil, sameAs: [String] = []) {
        self.name = name
        self.url = url
        self.logo = logo
        self.sameAs = sameAs
    }
}
