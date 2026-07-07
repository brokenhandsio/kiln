public import Foundation

/// A single loaded DocC documentation archive (`.doccarchive`) for one module:
/// its decoded pages, navigation index, and identity, plus lookups the renderer
/// uses to resolve links.
///
/// Produced by ``DocCArchiveLoader``. All heavy decoding happens once, up front;
/// the two lookup tables let the renderer resolve a `doc://` identifier (used by
/// topic/relationship sections and the reference map) or an archive-relative URL
/// path (used by reference `url`s) to the page it names.
public struct DocCArchive: Sendable {
    /// The module's display name, e.g. `"Queues"` (from `metadata.json`).
    public let moduleName: String
    /// The archive/bundle identifier, e.g. `"Queues"`.
    public let bundleID: String
    /// Every decoded page, sorted by ``DocCPage/path`` for deterministic output.
    public let pages: [DocCPage]
    /// The decoded navigation tree (`index/index.json`), if present.
    public let index: RenderIndex?
    /// The archive's root directory (used to resolve `images/`, `videos/`,
    /// `downloads/` assets referenced by pages).
    public let archiveURL: URL
    /// Non-fatal problems encountered while loading (a page that failed to decode,
    /// a missing index). Loading tolerates these and continues; the caller surfaces
    /// them as build warnings.
    public let loadIssues: [String]

    /// Pages keyed by archive-relative URL path, e.g. `/documentation/queues/queue`.
    /// Matches the `url` field carried by topic references.
    public let pagesByPath: [String: DocCPage]
    /// Pages keyed by `doc://` identifier, e.g.
    /// `doc://Queues/documentation/Queues/Queue`. Matches reference-map keys and
    /// the identifiers listed in topic/relationship sections.
    public let pagesByIdentifier: [String: DocCPage]

    init(
        moduleName: String,
        bundleID: String,
        pages: [DocCPage],
        index: RenderIndex?,
        archiveURL: URL,
        loadIssues: [String]
    ) {
        self.moduleName = moduleName
        self.bundleID = bundleID
        self.pages = pages
        self.index = index
        self.archiveURL = archiveURL
        self.loadIssues = loadIssues

        var byPath: [String: DocCPage] = [:]
        var byIdentifier: [String: DocCPage] = [:]
        byPath.reserveCapacity(pages.count)
        byIdentifier.reserveCapacity(pages.count)
        for page in pages {
            byPath[page.path] = page
            byIdentifier[page.identifier] = page
        }
        self.pagesByPath = byPath
        self.pagesByIdentifier = byIdentifier
    }

    /// The module's own landing page (the node whose path is `/documentation/<module>`),
    /// falling back to the first page.
    public var landingPage: DocCPage? {
        pagesByPath["/documentation/\(moduleName.lowercased())"] ?? pages.first
    }
}

/// One decoded page within a ``DocCArchive``.
public struct DocCPage: Sendable {
    /// The decoded render node — the page's content.
    public var node: RenderNode
    /// The archive-relative URL path, lower-cased, e.g. `/documentation/queues/queue`
    /// (derived from the JSON file's location under `data/`). This is the path DocC
    /// uses for hosting and the value carried by topic references' `url`.
    public var path: String
    /// The node's own `doc://` identifier, e.g. `doc://Queues/documentation/Queues/Queue`.
    public var identifier: String
    /// The source JSON file this page was decoded from.
    public var sourceFile: URL
}

/// A fatal error loading a ``DocCArchive`` (structural problems that make the
/// archive unusable). Per-page decode failures are non-fatal and collected in
/// ``DocCArchive/loadIssues`` instead.
public enum DocCArchiveError: Error, CustomStringConvertible {
    case archiveNotFound(URL)
    case missingMetadata(URL)
    case invalidMetadata(URL, underlying: any Error)
    case missingDataDirectory(URL)

    public var description: String {
        switch self {
        case .archiveNotFound(let url):
            return "DocC archive not found at \(url.path)."
        case .missingMetadata(let url):
            return "DocC archive at \(url.path) has no metadata.json."
        case .invalidMetadata(let url, let underlying):
            return "DocC archive at \(url.path) has an unreadable metadata.json: \(underlying)."
        case .missingDataDirectory(let url):
            return "DocC archive at \(url.path) has no data/ directory."
        }
    }
}
