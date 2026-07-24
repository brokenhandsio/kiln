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
/// Modules belong to a ``PackageVersion``, not to the package as a whole, because
/// a package's target set can change across major versions. Extract each ``Module``
/// into a variable and reuse it across the versions that ship it, so unchanged
/// modules aren't duplicated:
///
/// ```swift
/// let vapor = Module("Vapor", group: "Core", description: "Core web framework")
/// let xctVapor = Module("XCTVapor", group: "Testing")
/// let leafKit = Module("LeafKit", group: "Templating")
///
/// let site = KilnSite(
///     name: "Vapor API Docs",
///     url: "https://api.vapor.codes",
///     docc: DocCSite(
///         packages: [
///             APIPackage("vapor/vapor", versions: [
///                 PackageVersion("4", name: "4.x", ref: "vapor-4", isDefault: true, modules: [vapor, xctVapor]),
///                 PackageVersion("5-alpha", name: "5.0 (alpha)", ref: "main", isPrerelease: true, modules: [vapor, xctVapor]),
///             ]),
///             APIPackage("vapor/leaf-kit", versions: [.single(ref: "main", modules: [leafKit])]),
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

    /// Every module the site hosts, paired with its owning package — the set the
    /// catalog and module switcher list. Includes modules that only exist in a
    /// non-default version (surfaced at that version); see
    /// ``APIPackage/surfacedModules``.
    public var allModules: [(package: APIPackage, module: Module)] {
        packages.flatMap { package in package.surfacedModules.map { (package, $0.module) } }
    }
}

/// A single Swift package (git repository) whose DocC documentation is hosted.
///
/// A package is the *checkout unit*: one repository, built at one git ref at a
/// time, emitting its modules together. Because of that, a git ref is a property
/// of the package (via ``PackageVersion``), not of an individual module — you
/// cannot build two modules of the same package at different refs.
///
/// Modules belong to each ``PackageVersion`` rather than to the package, because a
/// package's target set can change across major versions. Extract shared modules
/// into variables and reuse them across the versions that ship them.
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
    /// This package's independent version lines, each carrying the modules it
    /// ships. Exactly one must be the default (served without a version segment in
    /// the URL). For a package with no version switcher, use
    /// ``PackageVersion/single(ref:modules:)``.
    public var versions: [PackageVersion]

    public init(
        _ repo: String,
        group: String? = nil,
        versions: [PackageVersion]
    ) {
        self.repo = repo
        self.group = group
        self.versions = versions
    }

    /// The package's default version (served at the module root). Falls back to
    /// the first version if none is flagged (validation rejects that case).
    public var defaultVersion: PackageVersion {
        versions.first(where: { $0.isDefault }) ?? versions[0]
    }

    /// The default version's modules — what the catalog and switcher list.
    public var defaultModules: [Module] {
        defaultVersion.modules
    }

    /// Every distinct module the package hosts, paired with the version at which
    /// it's surfaced in navigation (catalog, module switcher, cross-module links):
    /// the default version if it ships the module, otherwise the first version
    /// that does — its newest, given the usual default-first ordering. This keeps
    /// a module added only in a pre-release (e.g. a new target on the 5.0 line)
    /// discoverable, linking to that pre-release rather than a URL that 404s.
    public var surfacedModules: [(module: Module, version: PackageVersion)] {
        modulesAcrossVersions.map { entry in
            let version = entry.versions.first(where: { $0.isDefault }) ?? entry.versions[0]
            return (entry.module, version)
        }
    }

    /// Every distinct module across all versions (by name, in first-seen order),
    /// each paired with the versions that emit it.
    public var modulesAcrossVersions: [(module: Module, versions: [PackageVersion])] {
        var order: [String] = []
        var byName: [String: (module: Module, versions: [PackageVersion])] = [:]
        for version in versions {
            for module in version.modules {
                if byName[module.name] == nil {
                    order.append(module.name)
                    byName[module.name] = (module, [])
                }
                byName[module.name]?.versions.append(version)
            }
        }
        return order.compactMap { byName[$0] }
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
    /// An explicit badge label for a pre-release version (e.g. `"alpha"`, `"beta"`,
    /// `"rc"`), shown in the version/module switchers and on catalog cards. When
    /// `nil`, ``badge`` infers it from the ``id``/``name`` (falling back to
    /// `"beta"`); ignored for stable versions.
    public var prereleaseLabel: String?
    /// The major-version *line* this version belongs to, e.g. `4` or `5`. Used to
    /// align cross-module links across packages: a page on a package's `line`-N
    /// version links to the N-line of a multi-version dependency (Vapor 5 →
    /// RoutingKit 5), instead of the dependency's default.
    ///
    /// When `nil` the line is inferred from ``id`` then ``name`` (see ``majorLine``),
    /// which works for conventional ids like `"4"`/`"5-beta"`. Set it explicitly
    /// when neither encodes the major — e.g. a `main`-branch version whose id is
    /// `"latest"`, or a `main`-tracking `"4"` build that must stay on the 4 line.
    public var line: Int?
    /// The modules this version ships. A package's target set can differ across
    /// major versions, so each version declares its own; reuse ``Module`` values
    /// across versions to avoid duplication.
    public var modules: [Module]

    public init(
        _ id: String,
        name: String? = nil,
        ref: String,
        isDefault: Bool = false,
        isPrerelease: Bool = false,
        deprecated: Bool = false,
        prereleaseLabel: String? = nil,
        line: Int? = nil,
        modules: [Module]
    ) {
        self.id = id
        self.name = name ?? id
        self.ref = ref
        self.isDefault = isDefault
        self.isPrerelease = isPrerelease
        self.deprecated = deprecated
        self.prereleaseLabel = prereleaseLabel
        self.line = line
        self.modules = modules
    }

    /// This version's major line for cross-module link alignment: the explicit
    /// ``line`` if set, else the leading integer inferred from ``id``, else from
    /// ``name``. `nil` when none carry a number (e.g. a single-version package's
    /// `"default"`, which never needs alignment).
    public var majorLine: Int? {
        line ?? Self.majorLine(fromString: id) ?? Self.majorLine(fromString: name)
    }

    /// The leading integer of a version string — `"4"`, `"5-beta"`, `"5.0 (rc)"`,
    /// and `"6-rc.1"` yield 4/5/5/6; strings with no leading number yield `nil`.
    public static func majorLine(fromString string: String) -> Int? {
        var digits = ""
        for character in string {
            if character.isNumber { digits.append(character) }
            else if !digits.isEmpty { break }
            else if character == "." || character == "-" || character == "_" || character == " " { continue }
            else { break }
        }
        return Int(digits)
    }

    /// The single default version for a package with no version switcher. Built
    /// from `ref`, with an internal id (never shown, since it's served at the
    /// module root).
    public static func single(ref: String, modules: [Module]) -> PackageVersion {
        PackageVersion("default", ref: ref, isDefault: true, modules: modules)
    }

    /// The URL/output segment for this version: `""` for the default version,
    /// otherwise `"<id>/"`.
    public var urlSegment: String {
        isDefault ? "" : id + "/"
    }

    /// The switcher/catalog badge for this version, or `nil` for a stable one: the
    /// explicit ``prereleaseLabel`` if set, else the pre-release kind inferred from
    /// the ``id``/``name`` (`"alpha"`, `"beta"`, or `"rc"`), else `"beta"`.
    public var badge: String? {
        guard isPrerelease else { return nil }
        if let prereleaseLabel { return prereleaseLabel }
        let haystack = "\(id) \(name)".lowercased()
        return ["alpha", "beta", "rc"].first(where: haystack.contains) ?? "beta"
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
    /// An optional logo/image shown on the module's catalog card. A site-relative
    /// asset path (e.g. `"assets/logos/routing-kit.png"`, resolved against the
    /// site's mount path) or an absolute `http(s)` URL. `nil` renders no image.
    public var image: String?

    public init(
        _ name: String,
        title: String? = nil,
        group: String? = nil,
        description: String? = nil,
        image: String? = nil
    ) {
        self.name = name
        self.title = title
        self.group = group
        self.description = description
        self.image = image
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
            // Module names are unique across the whole site (they key the URL and
            // archive); the same name across a package's own versions is one module.
            let moduleNames = package.modulesAcrossVersions.map(\.module.name)
            if moduleNames.isEmpty {
                throw DocCConfigurationError.packageHasNoModules(repo: package.repo)
            }
            for name in moduleNames {
                if !seenModules.insert(name).inserted {
                    throw DocCConfigurationError.duplicateModuleName(name)
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
