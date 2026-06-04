public import Foundation

/// Errors thrown while loading content from disk.
public enum ContentError: Error, CustomStringConvertible {
    case contentDirectoryNotFound(String)
    case missingPage(logicalPath: String)

    public var description: String {
        switch self {
        case .contentDirectoryNotFound(let path):
            return "Content directory not found: \(path)"
        case .missingPage(let logicalPath):
            return "No markdown file found for navigation entry: \(logicalPath)"
        }
    }
}

/// Walks a content directory and builds a ``ContentStore``.
///
/// Files are matched to a locale by a suffix on the filename: `index.md` is the
/// default-language page, `index.de.md` is its German translation. Both map to
/// the same logical path (`index.md`), so navigation can reference one path and
/// Kiln resolves the right translation (or falls back) per language.
public struct ContentLoader: Sendable {
    public init() {}

    public func load(contentDirectory: URL, locales: Set<String>, defaultLocale: String) throws -> ContentStore {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: contentDirectory.path) else {
            throw ContentError.contentDirectoryNotFound(contentDirectory.path)
        }

        var pages: [String: [String: ContentPage]] = [:]

        let enumerator = fileManager.enumerator(
            at: contentDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension.lowercased() == "md" else { continue }

            let relativePath = Self.relativePath(of: item, from: contentDirectory)
            let (logicalPath, locale) = Self.resolveLocale(
                relativePath: relativePath,
                knownLocales: locales,
                defaultLocale: defaultLocale
            )

            let source = (try? String(contentsOf: item, encoding: .utf8)) ?? ""
            let (frontMatter, body) = FrontMatter.parse(from: source)
            let page = ContentPage(
                logicalPath: logicalPath,
                locale: locale,
                sourceURL: item,
                frontMatter: frontMatter,
                body: body
            )
            pages[logicalPath, default: [:]][locale] = page
        }

        return ContentStore(pages: pages)
    }

    /// Compute a path relative to the content directory, using `/` separators.
    static func relativePath(of url: URL, from base: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > baseComponents.count,
              Array(urlComponents.prefix(baseComponents.count)) == baseComponents else {
            return url.lastPathComponent
        }
        return urlComponents.dropFirst(baseComponents.count).joined(separator: "/")
    }

    /// Given `install/macos.de.md` and known locales, return the logical path
    /// (`install/macos.md`) and locale (`de`). Files without a recognised locale
    /// suffix belong to the default locale.
    static func resolveLocale(relativePath: String, knownLocales: Set<String>, defaultLocale: String) -> (logicalPath: String, locale: String) {
        let directory = (relativePath as NSString).deletingLastPathComponent
        let filename = (relativePath as NSString).lastPathComponent
        let components = filename.components(separatedBy: ".")

        // Need at least `name.locale.ext` (3 components) for a locale suffix.
        guard components.count >= 3 else {
            return (relativePath, defaultLocale)
        }

        let localeCandidate = components[components.count - 2]
        guard knownLocales.contains(localeCandidate) else {
            return (relativePath, defaultLocale)
        }

        // Drop the locale segment to form the logical filename.
        var logicalComponents = components
        logicalComponents.remove(at: logicalComponents.count - 2)
        let logicalFilename = logicalComponents.joined(separator: ".")
        let logicalPath = directory.isEmpty ? logicalFilename : "\(directory)/\(logicalFilename)"
        return (logicalPath, localeCandidate)
    }
}
