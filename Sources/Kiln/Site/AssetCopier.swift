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

    /// Copy every non-markdown, non-hidden file from the content directory to
    /// the output root, preserving relative paths.
    func copyContentAssets(from contentDirectory: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: contentDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let item = enumerator.nextObject() as? URL {
            let isRegularFile = (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isRegularFile, item.pathExtension.lowercased() != "md" else { continue }

            let relativePath = ContentLoader.relativePath(of: item, from: contentDirectory)
            let destination = outputDirectory.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: item, to: destination)
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
