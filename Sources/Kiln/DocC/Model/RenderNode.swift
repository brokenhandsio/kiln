/// A single decoded DocC render-JSON page — the machine-readable representation
/// of one symbol or article that Kiln renders into its theme.
///
/// This models the subset of DocC's `RenderNode` (render JSON `schemaVersion`
/// 0.3.x) that Kiln consumes. It is decode-only and **lenient**: constructs we
/// don't recognise decode to `.unknown` cases (see ``DocCDiagnostics``) rather
/// than failing, so the model survives additive DocC schema changes.
///
/// One of these is decoded from each `data/documentation/**.json` file in a
/// `.doccarchive`.
public struct RenderNode: Decodable, Sendable {
    /// The render-JSON schema version this node was produced with (e.g. 0.3.0).
    public var schemaVersion: SemanticVersion
    /// The node's own identifier (its `doc://` URL and interface language).
    public var identifier: Identifier
    /// Whether this page is a symbol, an article, etc.
    public var kind: Kind
    /// Title, symbol kind, declaration fragments, availability, and so on.
    public var metadata: RenderMetadata
    /// The one-line summary shown under the title and in topic cards.
    public var abstract: [RenderInlineContent]?
    /// The deprecation message shown in a prominent callout when the symbol is
    /// deprecated (from `@available(*, deprecated, message:)` or a
    /// `@DeprecationSummary`). Absent for non-deprecated symbols.
    public var deprecationSummary: [RenderBlockContent]?
    /// The breadcrumb ancestry (`doc://` identifier chains).
    public var hierarchy: RenderHierarchy?
    /// The main body: declarations, parameters, discussion, and the like.
    public var primaryContentSections: [RenderPrimarySection]?
    /// Curated child links ("Topics"), grouped with headings.
    public var topicSections: [TopicGroup]?
    /// Protocol conformances and sub/superclass relationships.
    public var relationshipsSections: [RelationshipsSection]?
    /// Default protocol-implementation links.
    public var defaultImplementationsSections: [TopicGroup]?
    /// "See Also" links.
    public var seeAlsoSections: [TopicGroup]?
    /// The reference map: every `doc://`/asset identifier this page mentions,
    /// resolved to a title/url/abstract (topics) or an asset (images), used to
    /// render links, symbol cards, and images. Keyed by identifier.
    public var references: [String: RenderReference]?

    /// A node's own identity.
    public struct Identifier: Decodable, Sendable {
        /// The `doc://<bundle>/documentation/…` URL identifying this page.
        public var url: String
        /// The source language, e.g. `"swift"`.
        public var interfaceLanguage: String
    }

    /// The kind of page a ``RenderNode`` represents.
    ///
    /// Kiln renders ``symbol`` and ``article`` today; tutorial-family kinds are
    /// recognised so they can be skipped deliberately, and anything else lands in
    /// ``unknown``.
    public enum Kind: Sendable, Equatable {
        case symbol
        case article
        case tutorial
        case overview
        case project
        case unknown(String)
    }
}

extension RenderNode.Kind: Decodable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "symbol": self = .symbol
        case "article": self = .article
        case "tutorial": self = .tutorial
        case "overview": self = .overview
        case "project": self = .project
        default:
            decoder.recordUnknownDocC(raw, at: "node kind")
            self = .unknown(raw)
        }
    }
}

/// A `major.minor.patch` version, as DocC encodes its schema versions.
public struct SemanticVersion: Decodable, Sendable, Equatable, Comparable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// A page's breadcrumb ancestry. For symbol/article nodes this is a list of
/// `doc://` identifier chains from the module root down to the page's parent.
public struct RenderHierarchy: Decodable, Sendable {
    public var paths: [[String]]?
}
