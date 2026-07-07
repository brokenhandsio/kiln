/// Resolves the `doc://` identifiers and asset references a ``RenderNode``
/// mentions into site links the renderer can emit.
///
/// A page carries everything needed to render *its own* links in its
/// ``RenderNode/references`` map — each entry gives a linked symbol's title, URL,
/// and kind. This wraps that map and maps DocC's archive-relative URLs (e.g.
/// `/documentation/queues/queue`) to Kiln's site URLs via ``mapPath``.
///
/// ``mapPath`` is injectable and defaults to the identity, so the renderer can be
/// tested in isolation now; the real DocC URL scheme (module/version prefixes) is
/// supplied later without touching the renderer.
public struct DocCLinkResolver: Sendable {
    /// The owning node's reference map, keyed by `doc://` identifier.
    public var references: [String: RenderReference]
    /// Maps an archive-relative DocC path/URL to a site-relative URL.
    public var mapPath: @Sendable (String) -> String

    public init(
        references: [String: RenderReference],
        mapPath: @escaping @Sendable (String) -> String = { $0 }
    ) {
        self.references = references
        self.mapPath = mapPath
    }

    /// A resolved link to another page.
    public struct ResolvedLink: Sendable {
        /// The site-relative href (already run through ``mapPath``).
        public var href: String
        /// The link's display title.
        public var title: String
        /// Whether the link targets a code symbol (rendered as inline code).
        public var isSymbol: Bool
    }

    /// The raw reference for an identifier, if present.
    public func reference(_ identifier: String) -> RenderReference? {
        references[identifier]
    }

    /// Resolve a topic identifier to a link, or `nil` if it isn't a topic with a
    /// URL (e.g. an unresolvable or asset reference).
    public func resolveTopic(_ identifier: String) -> ResolvedLink? {
        guard case .topic(let topic)? = references[identifier], let url = topic.url else { return nil }
        return ResolvedLink(
            href: mapPath(url),
            title: topic.title ?? identifier,
            isSymbol: topic.kind == "symbol"
        )
    }

    /// The plain title for an identifier, if any (used when a reference resolves
    /// to a topic without a URL, or an unresolvable link, so it still shows text).
    public func title(for identifier: String) -> String? {
        switch references[identifier] {
        case .topic(let topic)?: return topic.title
        case .unresolvable(let u)?: return u.title
        case .link(let l)?: return l.title
        default: return nil
        }
    }

    /// Resolve an image identifier to its best variant URL (run through
    /// ``mapPath``), preferring a light-appearance/@2x rendition when present.
    public func imageURL(_ identifier: String) -> String? {
        guard case .image(let image)? = references[identifier], !image.variants.isEmpty else { return nil }
        let preferred = image.variants.first { ($0.traits ?? []).contains("light") }
            ?? image.variants.first!
        return mapPath(preferred.url)
    }

    /// The alt text for an image identifier, if authored.
    public func imageAlt(_ identifier: String) -> String? {
        guard case .image(let image)? = references[identifier] else { return nil }
        return image.alt
    }
}
