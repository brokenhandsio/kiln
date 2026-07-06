/// A ``RenderNode``'s metadata: its display title, the kind of symbol it is, the
/// declaration fragments shown in navigators, availability, and owning modules.
public struct RenderMetadata: Decodable, Sendable {
    /// The page title, e.g. `"dispatch(_:_:maxRetryCount:delayUntil:id:)"`.
    public var title: String?
    /// The rendering role, e.g. `"symbol"`, `"collection"`, `"collectionGroup"`.
    public var role: String?
    /// A human heading for the role, e.g. `"Instance Method"`, `"Structure"`.
    public var roleHeading: String?
    /// The symbol kind driving icons/labels, e.g. `"method"`, `"struct"`,
    /// `"protocol"`, `"case"`, `"property"`.
    public var symbolKind: String?
    /// The compiler's stable unique symbol id (USR).
    public var externalID: String?
    /// The module an extension symbol was declared in, when different from the host.
    public var extendedModule: String?
    /// The module(s) this symbol belongs to.
    public var modules: [Module]?
    /// The short, subtitle-style declaration fragments (used in headers and cards).
    public var fragments: [DeclarationFragment]?
    /// The fragments a navigator uses to title this symbol.
    public var navigatorTitle: [DeclarationFragment]?
    /// Per-platform availability (introduced/deprecated versions, beta flags).
    public var platforms: [PlatformAvailability]?

    /// A module reference in metadata.
    public struct Module: Decodable, Sendable {
        public var name: String
        public var relatedModules: [String]?
    }
}

/// One token of a rendered declaration or navigator title.
///
/// A declaration is a sequence of these — keywords, punctuation, identifiers, and
/// type references. A `typeIdentifier` token may carry an `identifier` linking to
/// another page (resolved via the node's reference map), which is what makes
/// types in a signature clickable.
public struct DeclarationFragment: Decodable, Sendable {
    /// The visible text of the token.
    public var text: String
    /// The token role: `"keyword"`, `"text"`, `"identifier"`, `"typeIdentifier"`,
    /// `"genericParameter"`, `"externalParam"`, `"internalParam"`, `"attribute"`, …
    public var kind: String
    /// For a `typeIdentifier`, the `doc://` identifier of the referenced symbol
    /// (present only when that symbol is documented in the reference map).
    public var identifier: String?
    /// The compiler's stable id (USR) of the referenced symbol, when known.
    public var preciseIdentifier: String?
}

/// A symbol's availability on one platform.
public struct PlatformAvailability: Decodable, Sendable {
    public var name: String?
    public var introducedAt: String?
    public var deprecatedAt: String?
    public var beta: Bool?
    public var unavailable: Bool?
}
