// Uses FileManager's URL directory enumeration and URLResourceValues, which
// live in full Foundation (not FoundationEssentials).
import Foundation

/// Copies static assets into the output directory.
///
/// Theme assets (CSS/JS) land under `_kiln/` so they never clash with the
/// project's own files; the project's non-markdown content (images, custom
/// stylesheets/scripts referenced via `extraCSS`/`extraJavaScript`) is copied
/// to the site root preserving its structure, matching MkDocs' behaviour.
struct AssetCopier {
    let outputDirectory: URL

    /// Subdirectory of the output where theme assets are placed.
    static let themeAssetsPath = "_kiln"

    /// Copy the `css`/`js` folders of each theme directory into `_kiln/`,
    /// later directories overriding earlier ones (bundle first, custom last).
    func copyThemeAssets(from themeDirectories: [URL]) throws {
        let destination = outputDirectory.appendingPathComponent(Self.themeAssetsPath, isDirectory: true)
        for themeDirectory in themeDirectories {
            for subfolder in ["css", "js"] {
                let source = themeDirectory.appendingPathComponent(subfolder, isDirectory: true)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                try copyContents(of: source, into: destination.appendingPathComponent(subfolder, isDirectory: true))
            }
        }
    }

    /// Copy every non-markdown, non-hidden file from the content directory to the
    /// output (under `subdirectory`, empty for the default version), preserving
    /// relative paths. Directories in `excluding` are skipped wholesale — used to
    /// keep Kiln-managed input (the DocC `archives/` directory) out of the output.
    func copyContentAssets(from contentDirectory: URL, into subdirectory: String = "", excluding excludedDirectories: [URL] = []) throws {
        let fileManager = FileManager.default
        var destinationRoot = outputDirectory
        for component in subdirectory.split(separator: "/") {
            destinationRoot.appendPathComponent(String(component), isDirectory: true)
        }
        let excludedPaths = Set(excludedDirectories.map { $0.resolvingSymlinksInPath().path })
        guard let enumerator = fileManager.enumerator(
            at: contentDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let item = enumerator.nextObject() as? URL {
            // Don't descend into (or copy) an excluded directory, e.g. archives/.
            if !excludedPaths.isEmpty, excludedPaths.contains(item.resolvingSymlinksInPath().path) {
                enumerator.skipDescendants()
                continue
            }
            let isRegularFile = (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isRegularFile, item.pathExtension.lowercased() != "md" else { continue }

            let relativePath = ContentLoader.relativePath(of: item, from: contentDirectory)
            let destination = destinationRoot.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: item, to: destination)
        }
    }

    /// Copy a DocC archive's asset folders (`images`/`videos`/`downloads`) into a
    /// module's output directory, preserving structure — so a page's reference to
    /// `/images/foo.png` (rewritten to `<moduleRoot>images/foo.png`) resolves.
    /// Missing folders are skipped.
    func copyDocCAssets(from archiveDirectory: URL, into destination: URL) throws {
        for folder in ["images", "videos", "downloads"] {
            let source = archiveDirectory.appendingPathComponent(folder, isDirectory: true)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try copyContents(of: source, into: destination.appendingPathComponent(folder, isDirectory: true))
        }
    }

    /// Recursively copy the contents of `source` into `destination`, overwriting
    /// individual files (so a custom theme can replace a single asset).
    private func copyContents(of source: URL, into destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let item = enumerator.nextObject() as? URL {
            let isRegularFile = (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isRegularFile else { continue }
            let relativePath = ContentLoader.relativePath(of: item, from: source)
            let target = destination.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: item, to: target)
        }
    }
}
