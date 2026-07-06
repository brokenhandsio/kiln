/// The decoded `index/index.json` of a `.doccarchive` — the navigation tree
/// Kiln uses to build a module's sidebar.
///
/// This is a separate, smaller schema from ``RenderNode`` (render-index
/// `schemaVersion` 0.1.x). Each language maps to a forest of ``Entry`` nodes; a
/// module page sits at the root, with symbols nested beneath group markers.
public struct RenderIndex: Decodable, Sendable {
    /// The render-index schema version (e.g. 0.1.2).
    public var schemaVersion: SemanticVersion
    /// Navigation roots keyed by interface language (e.g. `"swift"`).
    public var interfaceLanguages: [String: [Entry]]
    /// Archive identifiers included in this index (multi-archive builds).
    public var includedArchiveIdentifiers: [String]?

    /// One node in the navigation tree.
    public struct Entry: Decodable, Sendable {
        /// The display title, e.g. `"QueuesCommand"` or a group marker like `"Classes"`.
        public var title: String
        /// The node type: a symbol kind (`"class"`, `"struct"`, `"method"`, …),
        /// `"module"`, or `"groupMarker"` (a non-navigable section heading).
        public var type: String
        /// The archive-relative page path, or nil for group markers.
        public var path: String?
        /// Child nodes, when this entry has a subtree.
        public var children: [Entry]?
        /// Whether the symbol is deprecated (for styling).
        public var deprecated: Bool?
        /// Whether the entry points outside this archive.
        public var external: Bool?
        /// Whether the symbol is beta.
        public var beta: Bool?

        /// Whether this entry is a non-navigable section heading (no page).
        public var isGroupMarker: Bool { type == "groupMarker" }

        private enum CodingKeys: String, CodingKey {
            case title, type, path, children, deprecated, external, beta
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
            self.path = try c.decodeIfPresent(String.self, forKey: .path)
            self.children = try c.decodeIfPresent([Entry].self, forKey: .children)
            self.deprecated = try c.decodeIfPresent(Bool.self, forKey: .deprecated)
            self.external = try c.decodeIfPresent(Bool.self, forKey: .external)
            self.beta = try c.decodeIfPresent(Bool.self, forKey: .beta)
        }
    }
}
