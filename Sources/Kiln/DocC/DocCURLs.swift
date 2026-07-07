#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Computes site URLs and on-disk output paths for the pages of one DocC module
/// at one version.
///
/// The DocC site is laid out **module-first**: the catalog at the root, then each
/// module under `/<module>/`, with a package's non-default versions nested one
/// level deeper (`/<module>/<version>/…`). DocC's own page paths carry a
/// redundant `/documentation/<module>` prefix (e.g. `/documentation/queues/queue`)
/// which is stripped, since the module already appears in the URL — so that page
/// is served at `/queues/queue/`.
public struct DocCURLs: Sendable {
    /// The mount path of the whole site, normalised (`""` or `"/docs"`).
    public let basePath: String
    /// This module's URL segment: the lower-cased module name, e.g. `"queues"`.
    public let moduleSegment: String
    /// This version's URL segment: `""` for the package's default version,
    /// otherwise `"<id>/"` (e.g. `"5-alpha/"`).
    public let versionSegment: String

    public init(moduleName: String, version: PackageVersion, basePath: String = "") {
        self.moduleSegment = moduleName.lowercased()
        self.versionSegment = version.urlSegment
        self.basePath = SiteURLs.normaliseBasePath(basePath)
    }

    /// The archive-relative documentation root for this module,
    /// e.g. `/documentation/queues`. DocC page paths start with this.
    private var documentationRoot: String { "/documentation/\(moduleSegment)" }

    /// Strip this module's `/documentation/<module>` prefix from an archive path,
    /// yielding the slash-free tail: `/documentation/queues/queue` → `"queue"`,
    /// `/documentation/queues/vapor/application` → `"vapor/application"`,
    /// `/documentation/queues` → `""`.
    func suffix(forDocCPath path: String) -> String {
        var tail = path
        if tail.hasPrefix(documentationRoot) {
            tail.removeFirst(documentationRoot.count)
        }
        while tail.hasPrefix("/") { tail.removeFirst() }
        while tail.hasSuffix("/") { tail.removeLast() }
        return tail
    }

    /// The site-relative URL for a DocC page path belonging to this module,
    /// e.g. `/queues/queue/` (or `/queues/5-alpha/queue/` for a non-default version).
    public func url(forDocCPath path: String) -> String {
        let suffix = suffix(forDocCPath: path)
        let tail = suffix.isEmpty ? "" : suffix + "/"
        return basePath + "/" + moduleSegment + "/" + versionSegment + tail
    }

    /// This module+version's root URL (its landing page), e.g. `/queues/` or
    /// `/queues/5-alpha/`.
    public var moduleRootURL: String {
        basePath + "/" + moduleSegment + "/" + versionSegment
    }

    /// The on-disk output file for a DocC page (`…/queues/queue/index.html`).
    public func outputFile(forDocCPath path: String, in outputDirectory: URL) -> URL {
        var url = outputDirectory
        url.appendPathComponent(moduleSegment, isDirectory: true)
        for component in versionSegment.split(separator: "/") {
            url.appendPathComponent(String(component), isDirectory: true)
        }
        for component in suffix(forDocCPath: path).split(separator: "/") {
            url.appendPathComponent(String(component), isDirectory: true)
        }
        url.appendPathComponent("index.html", isDirectory: false)
        return url
    }

    /// The relative path from a page back to the site mount root (e.g. `../../`),
    /// so asset/theme links resolve regardless of the page's depth.
    public func baseURL(forDocCPath path: String) -> String {
        var segments = [moduleSegment]
        segments += versionSegment.split(separator: "/").map(String.init)
        segments += suffix(forDocCPath: path).split(separator: "/").map(String.init)
        return segments.isEmpty ? "./" : String(repeating: "../", count: segments.count)
    }

    /// This module+version's output directory relative to the output root, e.g.
    /// `"queues"` or `"queues/5-alpha"` (used by the incremental-build manifest).
    public var relativeModuleDirectory: String {
        let version = versionSegment.hasSuffix("/") ? String(versionSegment.dropLast()) : versionSegment
        return version.isEmpty ? moduleSegment : moduleSegment + "/" + version
    }

    /// The on-disk directory this module+version is written into
    /// (`<output>/queues/` or `<output>/queues/5-alpha/`) — where its copied
    /// assets (images/videos/downloads) also land.
    public func moduleDirectory(in outputDirectory: URL) -> URL {
        var url = outputDirectory
        url.appendPathComponent(moduleSegment, isDirectory: true)
        for component in versionSegment.split(separator: "/") {
            url.appendPathComponent(String(component), isDirectory: true)
        }
        return url
    }
}

/// One module hosted by the DocC site, keyed for cross-module link resolution.
public struct DocCHostedModule: Sendable {
    /// The module's URL segment (lower-cased name), e.g. `"queues"`.
    public var moduleSegment: String
    /// The repo of the package this module belongs to (identifies "same package").
    public var packageRepo: String
    /// The URL segment of this module's package default version (`""` for default).
    public var defaultVersionSegment: String
}

/// The registry of every module a ``DocCSite`` hosts, plus the link-mapping logic
/// that turns DocC's archive-relative URLs into site URLs.
///
/// Cross-module link targeting follows the per-package versioning rule: a link
/// from a page to another module in the **same package** stays on the current
/// version; a link to a module in a **different package** goes to that module's
/// default version (versions are independent across packages).
public struct DocCModuleRegistry: Sendable {
    /// Hosted modules keyed by their DocC namespace (the lower-cased module name).
    public let modules: [String: DocCHostedModule]
    /// The site mount path, normalised.
    public let basePath: String

    public init(site: DocCSite, basePath: String = "") {
        self.basePath = SiteURLs.normaliseBasePath(basePath)
        var modules: [String: DocCHostedModule] = [:]
        for package in site.packages {
            let defaultVersionSegment = package.defaultVersion.urlSegment
            for module in package.defaultModules {
                let segment = module.name.lowercased()
                modules[segment] = DocCHostedModule(
                    moduleSegment: segment,
                    packageRepo: package.repo,
                    defaultVersionSegment: defaultVersionSegment
                )
            }
        }
        self.modules = modules
    }

    /// The catalog (landing) URL — the site root under the mount path.
    public var catalogURL: String { basePath + "/" }

    /// Whether the DocC namespace (lower-cased module name) is a module we host.
    public func hosts(namespace: String) -> Bool { modules[namespace] != nil }

    /// Resolve a `/documentation/<module>/…` path to its site URL, given the
    /// package/version of the page doing the linking. Returns `nil` if the target
    /// module isn't hosted (an external/unresolved reference).
    public func siteURL(forDocCPath path: String, currentPackageRepo: String, currentVersionSegment: String) -> String? {
        let prefix = "/documentation/"
        guard path.hasPrefix(prefix) else { return nil }
        let rest = path.dropFirst(prefix.count)
        let parts = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let namespace = parts.first.map(String.init), let hosted = modules[namespace] else { return nil }

        let suffix = parts.count > 1 ? String(parts[1]).trimmingSlashes() : ""
        // Same package → keep the current version; otherwise the target module's
        // package default version.
        let versionSegment = hosted.packageRepo == currentPackageRepo ? currentVersionSegment : hosted.defaultVersionSegment
        let tail = suffix.isEmpty ? "" : suffix + "/"
        return basePath + "/" + hosted.moduleSegment + "/" + versionSegment + tail
    }

    /// Build the archive-path → site-URL mapper for a page being rendered, wiring
    /// the current module's version context. Suitable as ``DocCLinkResolver/mapPath``.
    ///
    /// - `/documentation/<module>/…` paths route through ``siteURL(forDocCPath:currentPackageRepo:currentVersionSegment:)``
    ///   (falling back to the raw path when the target isn't hosted).
    /// - Other absolute paths (assets: `/images/…`, `/videos/…`, `/downloads/…`)
    ///   are mounted under the current module's root, where its assets are copied.
    /// - Absolute `http(s)`/`mailto` URLs pass through unchanged.
    public func linkMapper(current: DocCURLs, currentPackageRepo: String) -> @Sendable (String) -> String {
        let registry = self
        let moduleRoot = current.moduleRootURL
        let currentVersionSegment = current.versionSegment
        return { path in
            if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("mailto:") {
                return path
            }
            if path.hasPrefix("/documentation/") {
                return registry.siteURL(
                    forDocCPath: path,
                    currentPackageRepo: currentPackageRepo,
                    currentVersionSegment: currentVersionSegment
                ) ?? path
            }
            if path.hasPrefix("/") {
                return moduleRoot + String(path.dropFirst())
            }
            return path
        }
    }
}

extension String {
    /// Drop any leading/trailing `/`.
    fileprivate func trimmingSlashes() -> String {
        var s = self
        while s.hasPrefix("/") { s.removeFirst() }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
