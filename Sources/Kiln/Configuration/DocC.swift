/// Configuration for a DocC API-reference site: a collection of Swift packages
/// whose [DocC](https://www.swift.org/documentation/docc/) documentation is
/// ingested and rendered into the Kiln theme, with a module switcher and a
/// per-package version switcher.
///
/// Kiln does **not** compile the packages itself. A separate build step (Stage A)
/// runs `swift package generate-documentation` for each `(package, ref)` and
/// drops the resulting archives into ``archivesDirectory``; Kiln reads the
/// machine-readable JSON in those archives and renders it. This keeps Kiln
/// decoupled from the Swift toolchain — the only coupling is DocC's render JSON
/// schema, which is versioned and additive.
///
/// ```swift
/// let site = KilnSite(
///     name: "Vapor API Docs",
///     url: "https://api.vapor.codes",
///     docc: DocCSite(
///         packages: [
///             APIPackage(
///                 "vapor/vapor",
///                 modules: [
///                     Module("Vapor", group: "Core", description: "Core web framework"),
///                     Module("XCTVapor", group: "Testing"),
///                 ],
///                 versions: [
///                     PackageVersion("4", name: "4.x", ref: "vapor-4", isDefault: true),
///                     PackageVersion("5-alpha", name: "5.0 (alpha)", ref: "main", isPrerelease: true),
///                 ]
///             ),
///             APIPackage("vapor/leaf-kit", ref: "main", modules: [
///                 Module("LeafKit", group: "Templating"),
///             ]),
///         ],
///         groupOrder: ["Core", "Templating", "Testing"]
///     )
/// )
/// ```
public struct DocCSite: Sendable {
    /// The Swift packages whose DocC documentation this site hosts. Each package
    /// is a checkout unit (one git repository) that emits one or more
    /// ``Module``s and carries its own independent ``PackageVersion`` set.
    public var packages: [APIPackage]
    /// The order in which module ``Module/group``s are listed on the catalog
    /// landing page and in the module switcher. Groups not named here are sorted
    /// after the listed ones (by first appearance); modules with no group fall
    /// into a trailing `"Other"` bucket.
    public var groupOrder: [String]
    /// Directory containing the pre-built DocC archives, relative to the content
    /// directory. Stage-A CI writes one archive per `(package, ref)` here (see
    /// the type overview); Kiln reads them at build time.
    public var archivesDirectory: String

    public init(
        packages: [APIPackage],
        groupOrder: [String] = [],
        archivesDirectory: String = "archives"
    ) {
        self.packages = packages
        self.groupOrder = groupOrder
        self.archivesDirectory = archivesDirectory
    }

    /// Every module across every package, paired with its owning package.
    public var allModules: [(package: APIPackage, module: Module)] {
        packages.flatMap { package in package.modules.map { (package, $0) } }
    }
}

/// A single Swift package (git repository) whose DocC documentation is hosted.
///
/// A package is the *checkout unit*: one repository, built at one git ref at a
/// time, emitting all of its ``modules`` together. Because of that, a git ref is
/// a property of the package (via ``PackageVersion``), not of an individual
/// module — you cannot build two modules of the same package at different refs.
///
/// Each package owns an independent set of ``versions``: Vapor's `4.x`/`5.0-alpha`
/// lines have nothing to do with, say, FluentKit's versioning, so there is no
/// site-wide version axis — the version switcher is scoped to the package of the
/// module currently being viewed.
public struct APIPackage: Sendable {
    /// The repository identifier, e.g. `"vapor/vapor"`. Used to key
    /// per-``PackageVersion`` builds and to locate archives under
    /// ``DocCSite/archivesDirectory``.
    public var repo: String
    /// A default ``Module/group`` applied to any module in this package that
    /// doesn't set its own (packages usually sit in a single group, so this
    /// avoids repeating it on every module).
    public var group: String?
    /// The DocC targets this package emits. Built together from one checkout, so
    /// they share this package's ``versions``.
    public var modules: [Module]
    /// This package's independent version lines. Exactly one must be the default
    /// (served without a version segment in the URL).
    public var versions: [PackageVersion]

    /// Create a package with an explicit set of versions.
    public init(
        _ repo: String,
        group: String? = nil,
        modules: [Module],
        versions: [PackageVersion]
    ) {
        self.repo = repo
        self.group = group
        self.modules = modules
        self.versions = versions
    }

    /// Create a single-version package. Synthesises one default
    /// ``PackageVersion`` built from `ref`, for the common case of a package with
    /// no version switcher.
    public init(
        _ repo: String,
        ref: String,
        group: String? = nil,
        modules: [Module]
    ) {
        self.init(
            repo,
            group: group,
            modules: modules,
            versions: [PackageVersion("default", ref: ref, isDefault: true)]
        )
    }

    /// The package's default version (served at the module root). Falls back to
    /// the first version if none is flagged (validation rejects that case).
    public var defaultVersion: PackageVersion {
        versions.first(where: { $0.isDefault }) ?? versions[0]
    }

    /// The effective group for a module in this package: the module's own group,
    /// else the package default, else `nil` (the `"Other"` bucket).
    public func group(for module: Module) -> String? {
        module.group ?? group
    }
}

/// A version line of an ``APIPackage`` — a named git ref that Kiln builds and
/// exposes in the version switcher.
///
/// The default version is served at the module root (`/<module>/…`); every other
/// version is served under its ``id`` (`/<module>/<id>/…`).
public struct PackageVersion: Sendable {
    /// The version identifier, used as the URL segment for non-default versions
    /// (e.g. `"5-alpha"`). Must be non-empty, URL-safe (no `/` or whitespace),
    /// and unique within its package.
    public var id: String
    /// The display name shown in the version switcher, e.g. `"5.0 (alpha)"`.
    public var name: String
    /// The git branch or tag to build for this version, e.g. `"vapor-4"` or
    /// `"main"`. Identifies the `(repo, ref)` build cell handed to Stage A.
    public var ref: String
    /// Whether this is the default version, served at the module root. Exactly
    /// one version per package must be the default, and it must not be a
    /// pre-release.
    public var isDefault: Bool
    /// Whether this is a pre-release (alpha/beta/RC). Pre-releases can be
    /// published but are never the default; the switcher can label them.
    public var isPrerelease: Bool
    /// Whether this version is deprecated (used for switcher styling/labelling).
    public var deprecated: Bool

    public init(
        _ id: String,
        name: String? = nil,
        ref: String,
        isDefault: Bool = false,
        isPrerelease: Bool = false,
        deprecated: Bool = false
    ) {
        self.id = id
        self.name = name ?? id
        self.ref = ref
        self.isDefault = isDefault
        self.isPrerelease = isPrerelease
        self.deprecated = deprecated
    }

    /// The URL/output segment for this version: `""` for the default version,
    /// otherwise `"<id>/"`.
    public var urlSegment: String {
        isDefault ? "" : id + "/"
    }
}

/// A single DocC module (a Swift target) hosted on the site.
///
/// The ``name`` is the target/module name that keys its DocC archive; the other
/// fields are presentational — how the module appears on the catalog landing
/// page and in the module switcher.
public struct Module: Sendable {
    /// The DocC target name, e.g. `"Vapor"`. This is the archive key and, unless
    /// ``title`` is set, the display title.
    public var name: String
    /// An optional prettier display title (defaults to ``name``).
    public var title: String?
    /// The catalog/switcher section this module belongs to, e.g. `"Database"`.
    /// When `nil`, the owning ``APIPackage/group`` applies; when that's also
    /// `nil`, the module falls into the `"Other"` bucket.
    public var group: String?
    /// A short blurb shown on the module's catalog card.
    public var description: String?

    public init(
        _ name: String,
        title: String? = nil,
        group: String? = nil,
        description: String? = nil
    ) {
        self.name = name
        self.title = title
        self.group = group
        self.description = description
    }

    /// The title shown in the catalog and switcher (``title`` or ``name``).
    public var displayTitle: String {
        title ?? name
    }
}

/// Errors thrown while validating a ``DocCSite`` configuration.
public enum DocCConfigurationError: Error, CustomStringConvertible {
    case noPackages
    case duplicatePackageRepo(String)
    case packageHasNoModules(repo: String)
    case duplicateModuleName(String)
    case packageHasNoVersions(repo: String)
    case noDefaultVersion(repo: String)
    case multipleDefaultVersions(repo: String, ids: [String])
    case defaultVersionIsPrerelease(repo: String, id: String)
    case emptyVersionID(repo: String)
    case invalidVersionID(repo: String, id: String)
    case duplicateVersionID(repo: String, id: String)

    public var description: String {
        switch self {
        case .noPackages:
            return "DocCSite must declare at least one package."
        case .duplicatePackageRepo(let repo):
            return "Duplicate package repo '\(repo)'. Each package repo must be unique."
        case .packageHasNoModules(let repo):
            return "Package '\(repo)' must declare at least one module."
        case .duplicateModuleName(let name):
            return "Duplicate module name '\(name)'. Module names must be unique across the whole site (they key the URL and the archive)."
        case .packageHasNoVersions(let repo):
            return "Package '\(repo)' must declare at least one version."
        case .noDefaultVersion(let repo):
            return "Package '\(repo)' must declare exactly one default version (isDefault: true)."
        case .multipleDefaultVersions(let repo, let ids):
            return "Package '\(repo)' declares multiple default versions: \(ids.joined(separator: ", ")). Exactly one is allowed."
        case .defaultVersionIsPrerelease(let repo, let id):
            return "The default version '\(id)' of package '\(repo)' must not be a pre-release."
        case .emptyVersionID(let repo):
            return "Every version of package '\(repo)' must have a non-empty id."
        case .invalidVersionID(let repo, let id):
            return "Version id '\(id)' of package '\(repo)' is invalid: ids must not contain '/' or whitespace."
        case .duplicateVersionID(let repo, let id):
            return "Duplicate version id '\(id)' in package '\(repo)'. Version ids must be unique within a package."
        }
    }
}

extension DocCSite {
    /// Validate invariants that can't be expressed in the type system.
    ///
    /// Version ids are unique only *within* a package (two packages may both have
    /// a `"2"`); module names are unique across the whole site because they key
    /// both the URL and the archive.
    public func validate() throws {
        guard !packages.isEmpty else { throw DocCConfigurationError.noPackages }

        var seenRepos = Set<String>()
        var seenModules = Set<String>()
        for package in packages {
            if !seenRepos.insert(package.repo).inserted {
                throw DocCConfigurationError.duplicatePackageRepo(package.repo)
            }
            if package.modules.isEmpty {
                throw DocCConfigurationError.packageHasNoModules(repo: package.repo)
            }
            for module in package.modules {
                if !seenModules.insert(module.name).inserted {
                    throw DocCConfigurationError.duplicateModuleName(module.name)
                }
            }
            try validateVersions(package)
        }
    }

    private func validateVersions(_ package: APIPackage) throws {
        guard !package.versions.isEmpty else {
            throw DocCConfigurationError.packageHasNoVersions(repo: package.repo)
        }
        let defaults = package.versions.filter { $0.isDefault }
        if defaults.isEmpty { throw DocCConfigurationError.noDefaultVersion(repo: package.repo) }
        if defaults.count > 1 {
            throw DocCConfigurationError.multipleDefaultVersions(repo: package.repo, ids: defaults.map { $0.id })
        }
        if let def = defaults.first, def.isPrerelease {
            throw DocCConfigurationError.defaultVersionIsPrerelease(repo: package.repo, id: def.id)
        }
        var seen = Set<String>()
        for version in package.versions {
            if version.id.isEmpty { throw DocCConfigurationError.emptyVersionID(repo: package.repo) }
            if version.id.contains("/") || version.id.contains(where: \.isWhitespace) {
                throw DocCConfigurationError.invalidVersionID(repo: package.repo, id: version.id)
            }
            if !seen.insert(version.id).inserted {
                throw DocCConfigurationError.duplicateVersionID(repo: package.repo, id: version.id)
            }
        }
    }
}
