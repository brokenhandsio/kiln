// The `references` map resolves every identifier a page mentions — other symbols
// (`topic`), assets (`image`, `file`, `download`), external links (`link`), and
// dead links (`unresolvable`). Each entry is tagged by `"type"`; unrecognised
// types decode to `.unknown` (recorded via ``DocCDiagnostics``).

/// A resolved entry in a ``RenderNode``'s reference map.
public enum RenderReference: Sendable {
    /// Another documentation page (symbol or article).
    case topic(TopicReference)
    /// An image asset, with one or more trait-specific variants.
    case image(ImageReference)
    /// A video asset (`@Video`), with trait-specific variants and a poster image.
    case video(VideoReference)
    /// An external hyperlink.
    case link(LinkReference)
    /// A downloadable/file asset.
    case file(FileReference)
    /// A link DocC could not resolve (renders as plain text).
    case unresolvable(UnresolvableReference)
    /// A reference type not modelled by Kiln (recorded in ``DocCDiagnostics``).
    case unknown(type: String)

    /// The topic payload, if this is a `.topic` reference.
    public var topic: TopicReference? {
        if case .topic(let t) = self { return t }
        return nil
    }

    /// The image payload, if this is an `.image` reference.
    public var image: ImageReference? {
        if case .image(let i) = self { return i }
        return nil
    }
}

extension RenderReference: Decodable {
    private enum CodingKeys: String, CodingKey { case type }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "topic", "section", "symbol":
            self = .topic(try TopicReference(from: decoder))
        case "image":
            self = .image(try ImageReference(from: decoder))
        case "video":
            self = .video(try VideoReference(from: decoder))
        case "link":
            self = .link(try LinkReference(from: decoder))
        case "file", "download":
            self = .file(try FileReference(from: decoder))
        case "unresolvable":
            self = .unresolvable(try UnresolvableReference(from: decoder))
        default:
            decoder.recordUnknownDocC(type, at: "reference")
            self = .unknown(type: type)
        }
    }
}

/// A reference to another documentation page.
public struct TopicReference: Decodable, Sendable {
    /// This reference's own identifier (matches its key in the reference map).
    public var identifier: String
    /// The linked page's title.
    public var title: String?
    /// The linked page's archive-relative URL, e.g. `/documentation/queues/queue`.
    public var url: String?
    /// The linked page's kind, e.g. `"symbol"`, `"article"`.
    public var kind: String?
    /// The linked page's role, e.g. `"symbol"`, `"collection"`.
    public var role: String?
    /// The linked page's one-line summary (shown in symbol cards).
    public var abstract: [RenderInlineContent]?
    /// Subtitle declaration fragments (shown in symbol cards).
    public var fragments: [DeclarationFragment]?
    /// Navigator-title fragments.
    public var navigatorTitle: [DeclarationFragment]?
    /// Whether the linked symbol is deprecated.
    public var deprecated: Bool?

    private enum CodingKeys: String, CodingKey {
        case identifier, title, url, kind, role, abstract, fragments, navigatorTitle, deprecated
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try c.decode(String.self, forKey: .identifier)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.url = try c.decodeIfPresent(String.self, forKey: .url)
        self.kind = try c.decodeIfPresent(String.self, forKey: .kind)
        self.role = try c.decodeIfPresent(String.self, forKey: .role)
        self.abstract = try c.decodeIfPresent([RenderInlineContent].self, forKey: .abstract)
        self.fragments = try c.decodeIfPresent([DeclarationFragment].self, forKey: .fragments)
        self.navigatorTitle = try c.decodeIfPresent([DeclarationFragment].self, forKey: .navigatorTitle)
        self.deprecated = try c.decodeIfPresent(Bool.self, forKey: .deprecated)
    }
}

/// An image asset reference, resolved to trait-specific variants.
public struct ImageReference: Decodable, Sendable {
    public var identifier: String
    /// Alt text, when authored.
    public var alt: String?
    /// The available renditions (e.g. light/dark, 1x/2x).
    public var variants: [Variant]

    /// One image rendition and the display traits it applies to.
    public struct Variant: Decodable, Sendable {
        /// The archive-relative asset URL.
        public var url: String
        /// Display traits, e.g. `["2x", "light"]`.
        public var traits: [String]?
    }

    private enum CodingKeys: String, CodingKey { case identifier, alt, variants }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try c.decode(String.self, forKey: .identifier)
        self.alt = try c.decodeIfPresent(String.self, forKey: .alt)
        self.variants = try c.decodeIfPresent([Variant].self, forKey: .variants) ?? []
    }
}

/// A video asset reference (`@Video`), resolved to trait-specific variants and an
/// optional poster image (referenced by identifier, like any other image).
public struct VideoReference: Decodable, Sendable {
    public var identifier: String
    /// Alt text, when authored.
    public var alt: String?
    /// The identifier of the poster image shown before playback (resolve via the
    /// reference map like any image), when authored.
    public var poster: String?
    /// The available renditions (e.g. light/dark).
    public var variants: [ImageReference.Variant]

    private enum CodingKeys: String, CodingKey { case identifier, alt, poster, variants }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try c.decode(String.self, forKey: .identifier)
        self.alt = try c.decodeIfPresent(String.self, forKey: .alt)
        self.poster = try c.decodeIfPresent(String.self, forKey: .poster)
        self.variants = try c.decodeIfPresent([ImageReference.Variant].self, forKey: .variants) ?? []
    }
}

/// An external hyperlink reference.
public struct LinkReference: Decodable, Sendable {
    public var identifier: String?
    public var title: String?
    public var url: String?

    private enum CodingKeys: String, CodingKey { case identifier, title, url }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try c.decodeIfPresent(String.self, forKey: .identifier)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.url = try c.decodeIfPresent(String.self, forKey: .url)
    }
}

/// A file/download asset reference.
public struct FileReference: Decodable, Sendable {
    public var identifier: String
    public var url: String?

    private enum CodingKeys: String, CodingKey { case identifier, url }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try c.decode(String.self, forKey: .identifier)
        self.url = try c.decodeIfPresent(String.self, forKey: .url)
    }
}

/// A reference DocC could not resolve; rendered as plain text.
public struct UnresolvableReference: Decodable, Sendable {
    public var identifier: String?
    public var title: String?

    private enum CodingKeys: String, CodingKey { case identifier, title }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try c.decodeIfPresent(String.self, forKey: .identifier)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
    }
}
