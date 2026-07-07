public import Foundation

/// Loads a single DocC `.doccarchive` directory into an in-memory ``DocCArchive``.
///
/// The loader reads `metadata.json` for the module's identity, decodes every
/// `data/**/*.json` render node and the `index/index.json` navigation tree, and
/// records any unrecognised render-JSON constructs into the supplied
/// ``DocCDiagnostics`` (see that type for the leniency contract). It never
/// compiles Swift — it only consumes the pre-built archive.
///
/// Structural problems (no `metadata.json`, no `data/` directory) throw
/// ``DocCArchiveError``. A single malformed page or a missing index is tolerated
/// and recorded in ``DocCArchive/loadIssues`` so one bad node can't fail an
/// otherwise-good archive.
public struct DocCArchiveLoader {
    public init() {}

    /// Metadata read from an archive's `metadata.json`.
    private struct ArchiveMetadata: Decodable {
        var bundleDisplayName: String
        var bundleID: String?
    }

    /// Load the archive at `archiveURL`, recording unknown constructs into
    /// `diagnostics` (shared across archives when loading several).
    public func load(archiveURL: URL, diagnostics: DocCDiagnostics = DocCDiagnostics()) throws -> DocCArchive {
        let fm = FileManager.default
        guard fm.fileExists(atPath: archiveURL.path) else {
            throw DocCArchiveError.archiveNotFound(archiveURL)
        }

        // Identity.
        let metadataURL = archiveURL.appendingPathComponent("metadata.json")
        guard let metadataData = try? Data(contentsOf: metadataURL) else {
            throw DocCArchiveError.missingMetadata(archiveURL)
        }
        let metadata: ArchiveMetadata
        do {
            metadata = try JSONDecoder().decode(ArchiveMetadata.self, from: metadataData)
        } catch {
            throw DocCArchiveError.invalidMetadata(archiveURL, underlying: error)
        }

        // Pages.
        let dataDirectory = archiveURL.appendingPathComponent("data", isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dataDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            throw DocCArchiveError.missingDataDirectory(archiveURL)
        }

        let decoder = JSONDecoder()
        decoder.userInfo[.doccDiagnostics] = diagnostics

        var pages: [DocCPage] = []
        var issues: [String] = []
        for file in Self.jsonFiles(in: dataDirectory, using: fm) {
            do {
                let node = try decoder.decode(RenderNode.self, from: Data(contentsOf: file))
                pages.append(
                    DocCPage(
                        node: node,
                        path: Self.relativePath(of: file, under: dataDirectory),
                        identifier: node.identifier.url,
                        sourceFile: file
                    )
                )
            } catch {
                issues.append("failed to decode \(Self.relativePath(of: file, under: dataDirectory)): \(error)")
            }
        }
        pages.sort { $0.path < $1.path }

        // Navigation index (optional but expected).
        var index: RenderIndex?
        let indexURL = archiveURL.appendingPathComponent("index/index.json")
        if let indexData = try? Data(contentsOf: indexURL) {
            do {
                index = try decoder.decode(RenderIndex.self, from: indexData)
            } catch {
                issues.append("failed to decode index/index.json: \(error)")
            }
        } else {
            issues.append("no index/index.json found")
        }

        return DocCArchive(
            moduleName: metadata.bundleDisplayName,
            bundleID: metadata.bundleID ?? metadata.bundleDisplayName,
            pages: pages,
            index: index,
            archiveURL: archiveURL,
            loadIssues: issues
        )
    }

    // MARK: Helpers

    /// Every `*.json` file under `directory`, recursively.
    private static func jsonFiles(in directory: URL, using fm: FileManager) -> [URL] {
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
    }

    /// The archive-relative, lower-cased URL path a `data/` JSON file maps to,
    /// e.g. `…/data/documentation/queues/queue.json` → `/documentation/queues/queue`.
    /// This matches the `url` DocC assigns the page for hosting and in references.
    static func relativePath(of file: URL, under dataDirectory: URL) -> String {
        // Resolve symlinks on both sides so the prefix strip is robust to e.g. a
        // temp dir under `/var` (a symlink to `/private/var`) whose enumerated
        // file paths would otherwise not share the unresolved base prefix.
        var path = file.resolvingSymlinksInPath().path
        let prefix = dataDirectory.resolvingSymlinksInPath().path
        if path.hasPrefix(prefix) { path.removeFirst(prefix.count) }
        if path.hasSuffix(".json") { path.removeLast(".json".count) }
        if !path.hasPrefix("/") { path = "/" + path }
        return path
    }
}
