#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Kiln generates a static documentation website from a Swift-defined
/// ``KilnSite`` configuration and a directory of markdown content.
///
/// ```swift
/// let site = KilnSite(name: "My Docs", url: "https://example.com") {
///     Page("Welcome", "index.md")
/// }
/// try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "public")
/// ```
public enum Kiln {
    /// Build the site described by `site`, reading markdown from
    /// `contentDirectory` and writing the static site to `outputDirectory`.
    ///
    /// - Parameters:
    ///   - site: the site configuration.
    ///   - contentDirectory: directory containing markdown content.
    ///   - outputDirectory: directory to write the generated site into (created
    ///     fresh on each build).
    ///   - linkChecking: how to handle broken internal links (default `.warn`).
    public static func build(
        _ site: KilnSite,
        contentDirectory: URL,
        outputDirectory: URL,
        linkChecking: LinkChecking = .warn
    ) async throws {
        let generator = SiteGenerator(
            site: site,
            contentDirectory: contentDirectory,
            outputDirectory: outputDirectory,
            linkChecking: linkChecking
        )
        try await generator.build()
    }

    /// Convenience overload taking filesystem paths (resolved relative to the
    /// current working directory).
    public static func build(
        _ site: KilnSite,
        contentDirectory: String,
        outputDirectory: String,
        linkChecking: LinkChecking = .warn
    ) async throws {
        try await build(
            site,
            contentDirectory: URL(fileURLWithPath: contentDirectory),
            outputDirectory: URL(fileURLWithPath: outputDirectory),
            linkChecking: linkChecking
        )
    }
}
