#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif
public import LeafKit

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
    ///   - incremental: when `true`, a DocC build reuses the previous output for
    ///     modules whose inputs are unchanged (see ``DocCBuildManifest``), instead
    ///     of wiping the output and re-rendering everything. Safe to leave on for
    ///     local iteration; a fresh checkout (no manifest) still does a full build.
    ///   - leafTags: custom Leaf tags, merged over Kiln's built-ins (a caller tag
    ///     wins a name clash).
    public static func build(
        _ site: KilnSite,
        contentDirectory: URL,
        outputDirectory: URL,
        linkChecking: LinkChecking = .warn,
        incremental: Bool = false,
        leafTags: [String: any LeafTag] = [:]
    ) async throws {
        let generator = SiteGenerator(
            site: site,
            contentDirectory: contentDirectory,
            outputDirectory: outputDirectory,
            linkChecking: linkChecking,
            incremental: incremental,
            leafTags: leafTags
        )
        try await generator.build()
    }

    /// Convenience overload taking filesystem paths (resolved relative to the
    /// current working directory).
    public static func build(
        _ site: KilnSite,
        contentDirectory: String,
        outputDirectory: String,
        linkChecking: LinkChecking = .warn,
        incremental: Bool = false,
        leafTags: [String: any LeafTag] = [:]
    ) async throws {
        try await build(
            site,
            contentDirectory: URL(fileURLWithPath: contentDirectory),
            outputDirectory: URL(fileURLWithPath: outputDirectory),
            linkChecking: linkChecking,
            incremental: incremental,
            leafTags: leafTags
        )
    }

    /// Stage A: build the DocC `.doccarchive`s the render step reads, checking out
    /// each package at its ref and running `swift package generate-documentation`.
    /// No-op for a site without a ``KilnSite/docc`` configuration.
    ///
    /// This shells out to git and the Swift toolchain (the only part of Kiln that
    /// does), so call it before ``build(_:contentDirectory:outputDirectory:linkChecking:incremental:leafTags:)``
    /// when you want a single command to produce archives *and* the site. CI can
    /// instead restore cached archives and pass `rebuild:` to regenerate only what
    /// changed.
    @discardableResult
    public static func buildDocCArchives(
        _ site: KilnSite,
        contentDirectory: String,
        checkoutDirectory: String = ".build/docc-sources",
        rebuild: DocCArchiveBuilder.Rebuild = .missing
    ) throws -> [String] {
        guard let docc = site.docc else { return [] }
        let builder = DocCArchiveBuilder(
            docc: docc,
            contentDirectory: URL(fileURLWithPath: contentDirectory),
            checkoutDirectory: URL(fileURLWithPath: checkoutDirectory)
        )
        return try builder.build(rebuild: rebuild)
    }
}
