// The main body of a symbol/article page is a list of "primary content"
// sections, each tagged by a `"kind"`. As with content types, unrecognised kinds
// decode to `.unknown` (recorded via ``DocCDiagnostics``) rather than throwing.

/// One section of a page's primary content.
public enum RenderPrimarySection: Sendable {
    /// The rendered declaration(s) — the symbol's signature, per platform/language.
    case declarations([Declaration])
    /// Documented parameters, each with a name and prose.
    case parameters([ParameterDoc])
    /// Free-form discussion/overview prose (also carries "Return Value",
    /// "Discussion", etc. as headed subsections).
    case content([RenderBlockContent])
    /// Enumerated possible values (e.g. for a string-backed option), each with prose.
    case possibleValues([PossibleValue])
    /// "Mentioned in" — identifiers of articles that reference this symbol.
    case mentions([String])
    /// A section kind not modelled by Kiln (recorded in ``DocCDiagnostics``).
    case unknown(kind: String)

    /// One rendered declaration variant.
    public struct Declaration: Decodable, Sendable {
        /// Platforms this declaration applies to (nil = all).
        public var platforms: [String]?
        /// The declaration tokens (keywords, identifiers, type references).
        public var tokens: [DeclarationFragment]
        /// Source languages this declaration applies to, e.g. `["swift"]`.
        public var languages: [String]?
    }

    /// One documented parameter.
    public struct ParameterDoc: Decodable, Sendable {
        public var name: String
        public var content: [RenderBlockContent]
    }

    /// One documented possible value.
    public struct PossibleValue: Decodable, Sendable {
        public var name: String
        public var content: [RenderBlockContent]?
    }
}

extension RenderPrimarySection: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, declarations, parameters, content, values, mentions
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "declarations":
            self = .declarations(try c.decodeIfPresent([Declaration].self, forKey: .declarations) ?? [])
        case "parameters":
            self = .parameters(try c.decodeIfPresent([ParameterDoc].self, forKey: .parameters) ?? [])
        case "content":
            self = .content(try c.decodeIfPresent([RenderBlockContent].self, forKey: .content) ?? [])
        case "possibleValues":
            self = .possibleValues(try c.decodeIfPresent([PossibleValue].self, forKey: .values) ?? [])
        case "mentions":
            self = .mentions(try c.decodeIfPresent([String].self, forKey: .mentions) ?? [])
        default:
            decoder.recordUnknownDocC(kind, at: "primary content section")
            self = .unknown(kind: kind)
        }
    }
}

/// A curated group of links — a "Topics" group, a "See Also" group, or a
/// "Default Implementations" group. The `identifiers` resolve against the node's
/// reference map.
public struct TopicGroup: Decodable, Sendable {
    /// The group heading, e.g. `"Classes"` (absent for anonymous groups).
    public var title: String?
    /// The `doc://` identifiers of the members, in curated order.
    public var identifiers: [String]
    /// The heading anchor slug.
    public var anchor: String?
    /// Whether DocC synthesised this group (vs. author-curated).
    public var generated: Bool?

    private enum CodingKeys: String, CodingKey { case title, identifiers, anchor, generated }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.identifiers = try c.decodeIfPresent([String].self, forKey: .identifiers) ?? []
        self.anchor = try c.decodeIfPresent(String.self, forKey: .anchor)
        self.generated = try c.decodeIfPresent(Bool.self, forKey: .generated)
    }
}

/// A relationships section: protocol conformances, or sub/superclass links.
public struct RelationshipsSection: Decodable, Sendable {
    /// The relationship kind: `"conformsTo"`, `"inheritsFrom"`, `"inheritedBy"`, …
    public var type: String
    /// The section heading, e.g. `"Conforms To"`.
    public var title: String?
    /// The `doc://` identifiers of the related symbols.
    public var identifiers: [String]

    private enum CodingKeys: String, CodingKey { case type, title, identifiers }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(String.self, forKey: .type)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.identifiers = try c.decodeIfPresent([String].self, forKey: .identifiers) ?? []
    }
}
