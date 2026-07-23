// Full Foundation: this uses `Process` (git + swift package generate-documentation)
// and file I/O, which live in Foundation proper.
import Foundation

/// Stage A of the DocC pipeline: build the `.doccarchive`s that ``DocCRenderPhase``
/// (Stage B) reads. For each `(package, version)` in a ``DocCSite`` it checks the
/// repo out at the version's ref, ensures the swift-docc-plugin is available, runs
/// `swift package generate-documentation`, and drops the archive at
/// `<archivesDirectory>/<versionID>/<Module>.doccarchive`.
///
/// This is the **one** place Kiln shells out to the Swift toolchain and git — the
/// rendering core (``Kiln/build(_:contentDirectory:outputDirectory:incremental:linkChecking:)``)
/// still only *reads* pre-built archives. Archive generation is opt-in, so a
/// static (non-DocC) site never touches a compiler; a DocC site can build its own
/// archives on demand (`swift run` / `kiln serve`) rather than requiring a
/// separate manual step. CI layers caching (e.g. S3) *around* this — Kiln itself
/// treats an already-present archive as done unless a rebuild is forced.
public struct DocCArchiveBuilder: Sendable {
    /// Which archives to (re)generate. Missing archives are always built; these
    /// select what to *force*-rebuild on top of that.
    public enum Rebuild: Sendable, Equatable {
        /// Build only archives that don't already exist (the default).
        case missing
        /// Force-rebuild every configured archive.
        case all
        /// Force-rebuild the selected packages (see ``Target``).
        case targets([Target])

        /// A `--rebuild` selector: a package by repo (`jwt-kit` or its full
        /// `vapor/jwt-kit`), optionally pinned to one ref (`routing-kit@main`). A
        /// bare repo forces all the package's versions; `repo@ref` forces only the
        /// version(s) built from that ref.
        public struct Target: Sendable, Equatable {
            public var repo: String
            public var ref: String?

            public init(repo: String, ref: String? = nil) {
                self.repo = repo
                self.ref = ref
            }

            public init(_ spec: String) {
                if let at = spec.firstIndex(of: "@") {
                    self.init(repo: String(spec[..<at]), ref: String(spec[spec.index(after: at)...]))
                } else {
                    self.init(repo: spec, ref: nil)
                }
            }
        }

        public static func rebuilding(_ specs: [String]) -> Rebuild {
            .targets(specs.map(Target.init))
        }

        func forces(package: APIPackage, version: PackageVersion) -> Bool {
            switch self {
            case .missing: return false
            case .all: return true
            case .targets(let targets):
                return targets.contains { target in
                    Self.matches(selector: target.repo, repo: package.repo)
                        && (target.ref == nil || target.ref == version.ref)
                }
            }
        }

        private static func matches(selector: String, repo: String) -> Bool {
            let selector = selector.lowercased(), repo = repo.lowercased()
            return repo == selector || repo.hasSuffix("/" + selector)
        }
    }

    /// Errors that abort a build (per-archive tool failures throw these).
    enum BuildError: Error, CustomStringConvertible {
        case gitFailed(repo: String, ref: String, status: Int32)
        case noManifest(repo: String)
        case generateFailed(module: String, repo: String, ref: String, status: Int32)
        case archiveNotProduced(module: String, at: String)

        public var description: String {
            switch self {
            case .gitFailed(let repo, let ref, let status):
                return "git checkout of \(repo) @ \(ref) failed (exit \(status))"
            case .noManifest(let repo):
                return "no Package.swift manifest found in checkout of \(repo)"
            case .generateFailed(let module, let repo, let ref, let status):
                return "generate-documentation for \(module) (\(repo) @ \(ref)) failed (exit \(status))"
            case .archiveNotProduced(let module, let at):
                return "generate-documentation for \(module) produced no archive at \(at)"
            }
        }
    }

    let docc: DocCSite
    /// The content directory (archives are written under its `archivesDirectory`).
    let contentDirectory: URL
    /// Where package repos are cloned/cached between runs (git fetch + checkout).
    let checkoutDirectory: URL
    /// Base URL for resolving a package's `owner/name` repo to a clone URL.
    let gitHost: String
    /// Resolve links *between* hosted modules (a symbol's cross-module "Conforms
    /// To", a foreign type it extends, …) instead of rendering them as plain text.
    ///
    /// Builds each archive with DocC's experimental external-link support, in
    /// package-dependency order, passing each already-built dependency archive to
    /// its dependents. The rendered site needs no changes: the resolved
    /// `/documentation/<module>/…` URLs route through ``DocCModuleRegistry``.
    let crossModuleLinks: Bool

    init(
        docc: DocCSite,
        contentDirectory: URL,
        checkoutDirectory: URL,
        gitHost: String = "https://github.com",
        crossModuleLinks: Bool = false
    ) {
        self.docc = docc
        self.contentDirectory = contentDirectory
        self.checkoutDirectory = checkoutDirectory
        self.gitHost = gitHost
        self.crossModuleLinks = crossModuleLinks
    }

    /// A line-oriented progress sink (defaults to stderr so it doesn't pollute
    /// piped stdout).
    typealias Log = @Sendable (String) -> Void

    /// Generate the archives selected by `rebuild`. Returns the module names built
    /// (skipped ones — already present and not forced — are not included).
    @discardableResult
    func build(rebuild: Rebuild = .missing, log: Log? = nil) throws -> [String] {
        // Default to stderr so progress doesn't pollute piped stdout. (Can't live
        // in the default argument: FileHandle isn't public-visible there.)
        let log: Log = log ?? { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
        let fileManager = FileManager.default
        var archivesBase = contentDirectory
        for component in docc.archivesDirectory.split(separator: "/") {
            archivesBase.appendPathComponent(String(component), isDirectory: true)
        }
        try fileManager.createDirectory(at: checkoutDirectory, withIntermediateDirectories: true)

        // Cross-module build state (dependency graph + the link surfaces each
        // archive was built against), persisted beside the archives.
        var state = crossModuleLinks ? loadLinkState(archivesBase) : LinkState()
        var dependencies: [String: Set<String>] = state.dependencies.mapValues(Set.init)

        // Packages that need *some* work regardless of the dependency graph. Their
        // checkouts give us fresh edges before the order is decided.
        if crossModuleLinks {
            log("🔗 cross-module links: resolving package dependency order")
            for package in docc.packages {
                let needsWork = package.versions.contains { version in
                    rebuild.forces(package: package, version: version) || version.modules.contains { module in
                        let archive = DocCRenderPhase.archiveURL(module: module, version: version, in: archivesBase)
                        return !fileManager.fileExists(atPath: archive.path) || lacksLinkMetadata(archive)
                    }
                }
                let checkout = checkoutDirectory.appendingPathComponent(repoSlug(package.repo))
                if needsWork, let ref = package.versions.first?.ref {
                    try checkoutRepo(package.repo, ref: ref, into: checkout, log: log)
                    dependencies[package.repo] = hostedDependencies(in: checkout, log: log)
                } else if dependencies[package.repo] == nil,
                          fileManager.fileExists(atPath: checkout.appendingPathComponent(".git").path) {
                    // Backfill edges from a checkout we already have. Without this a
                    // fully-built site never records its graph, so the staleness
                    // cascade below would have nothing to work from. Packages with no
                    // local checkout are left for whenever they're next built —
                    // cloning them just to read a manifest isn't worth it.
                    dependencies[package.repo] = hostedDependencies(in: checkout, log: log)
                }
            }
        }

        // Dependencies first, so a rebuilt archive's fresh timestamp is visible to
        // its dependents as we walk — which is what makes staleness cascade.
        let ordered = crossModuleLinks
            ? Self.dependencyOrdered(docc.packages, dependencies: dependencies, log: log)
            : docc.packages

        var built: [String] = []
        for package in ordered {
            // Decide the work for this package *now* (not upfront): anything
            // rebuilt earlier in this walk has already bumped its mtime.
            var work: [(version: PackageVersion, modules: [Module])] = []
            for version in package.versions {
                let forced = rebuild.forces(package: package, version: version)
                let modules = version.modules.filter { module in
                    let archive = DocCRenderPhase.archiveURL(module: module, version: version, in: archivesBase)
                    if forced || !fileManager.fileExists(atPath: archive.path) { return true }
                    guard crossModuleLinks else { return false }
                    // Built before cross-module links were enabled: it can neither
                    // resolve its own links nor serve as a dependency for others.
                    if lacksLinkMetadata(archive) {
                        log("♻️  \(module.name)@\(version.id): no link metadata — rebuilding")
                        return true
                    }
                    // A dependency's link surface changed since this was built, so
                    // its cross-module links may be stale or dangling.
                    let key = archiveKey(archive, in: archivesBase)
                    let current = currentLinkInputs(for: package, dependencies: dependencies, archivesBase: archivesBase)
                    if linkInputsChanged(recorded: state.linkInputs[key], current: current) {
                        log("♻️  \(module.name)@\(version.id): a dependency changed — rebuilding for fresh links")
                        return true
                    }
                    // No baseline recorded (archive predates this tracking): adopt
                    // the current inputs rather than forcing a mass rebuild.
                    if state.linkInputs[key] == nil { state.linkInputs[key] = current }
                    return false
                }
                if !modules.isEmpty { work.append((version, modules)) }
            }
            guard !work.isEmpty else { continue }

            let checkout = checkoutDirectory.appendingPathComponent(repoSlug(package.repo))
            for (version, modules) in work {
                log("📦 \(package.repo) @ \(version.ref) → \(modules.map(\.name).joined(separator: ", "))")
                try checkoutRepo(package.repo, ref: version.ref, into: checkout, log: log)
                try ensurePluginAvailable(in: checkout, repo: package.repo, log: log)
                // A package pulled in by the staleness cascade hasn't had its edges
                // read yet; record them so later builds can order and invalidate it.
                if crossModuleLinks && dependencies[package.repo] == nil {
                    dependencies[package.repo] = hostedDependencies(in: checkout, log: log)
                }
                // Archives of the hosted packages this one depends on, for link
                // resolution. Only ones already on disk (built earlier in this run,
                // or cached from a previous one) are passed.
                let dependencyArchives = crossModuleLinks
                    ? existingDependencyArchives(for: package, dependencies: dependencies, in: archivesBase)
                    : []
                for module in modules {
                    let archive = DocCRenderPhase.archiveURL(module: module, version: version, in: archivesBase)
                    // A package's own modules can reference each other too (e.g.
                    // XCTFluent → FluentKit), and each is a separate DocC build, so
                    // pass the siblings' archives alongside the dependencies'.
                    let siblings = crossModuleLinks
                        ? existingSiblingArchives(of: module, in: version, package: package, archivesBase: archivesBase)
                        : []
                    try generate(module: module, package: package, version: version,
                                 checkout: checkout, archive: archive,
                                 dependencyArchives: dependencyArchives + siblings, log: log)
                    built.append(module.name)
                    if crossModuleLinks {
                        // Record the link surfaces this archive was just built
                        // against, so a later change to any of them invalidates it.
                        state.linkInputs[archiveKey(archive, in: archivesBase)] =
                            currentLinkInputs(for: package, dependencies: dependencies, archivesBase: archivesBase)
                    }
                }
            }
        }
        if crossModuleLinks {
            state.dependencies = dependencies.mapValues { $0.sorted() }
            saveLinkState(state, in: archivesBase, log: log)
        }
        return built
    }

    // MARK: Cache invalidation

    /// Whether an archive predates cross-module linking — no link metadata means it
    /// can neither resolve its own cross-module links nor act as a dependency, so
    /// leaving it cached would silently pin the site to the old behaviour.
    func lacksLinkMetadata(_ archive: URL) -> Bool {
        !FileManager.default.fileExists(atPath: archive.appendingPathComponent("linkable-entities.json").path)
    }

    /// A content hash of an archive's *link surface* — the `linkable-entities.json`
    /// DocC writes under external-link support. That file is exactly what dependents
    /// resolve their cross-module links against, so if it's unchanged their links
    /// cannot have changed.
    ///
    /// Deliberately content-based, not timestamp-based: archives restored from a CI
    /// cache get arbitrary mtimes, and a dependency that merely *looked* newer would
    /// otherwise spuriously rebuild everything downstream — defeating the cache.
    func linkSurfaceHash(_ archive: URL) -> String? {
        guard let data = try? Data(contentsOf: archive.appendingPathComponent("linkable-entities.json")) else {
            return nil
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325   // FNV-1a, matching DocCFingerprint
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// A stable key for an archive inside the archives directory
    /// (`<versionID>/<Module>.doccarchive`), so recorded state survives moves.
    func archiveKey(_ archive: URL, in archivesBase: URL) -> String {
        let base = archivesBase.standardizedFileURL.path
        let path = archive.standardizedFileURL.path
        guard path.hasPrefix(base) else { return archive.lastPathComponent }
        return String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// The current link-surface hashes of every archive `package` resolves against.
    func currentLinkInputs(
        for package: APIPackage,
        dependencies: [String: Set<String>],
        archivesBase: URL
    ) -> [String: String] {
        var inputs: [String: String] = [:]
        for dependencyArchive in existingDependencyArchives(for: package, dependencies: dependencies, in: archivesBase) {
            if let hash = linkSurfaceHash(dependencyArchive) {
                inputs[archiveKey(dependencyArchive, in: archivesBase)] = hash
            }
        }
        return inputs
    }

    /// Whether the link surface an archive was built against has since changed.
    /// `recorded == nil` means there's no baseline yet (an archive from before this
    /// tracking existed), in which case the caller adopts the current inputs as the
    /// baseline rather than forcing a mass rebuild.
    func linkInputsChanged(recorded: [String: String]?, current: [String: String]) -> Bool {
        guard let recorded else { return false }
        return recorded != current
    }

    /// Cross-module build state, kept with the archives so it travels with them
    /// (including through CI's archive cache).
    ///
    /// - `dependencies`: repo → hosted repos it depends on, so a later build can
    ///   order and invalidate packages it never checks out.
    /// - `linkInputs`: archive key → the link-surface hashes it was built against,
    ///   so a dependency's *content* change invalidates exactly its dependents.
    struct LinkState: Codable {
        var dependencies: [String: [String]] = [:]
        var linkInputs: [String: [String: String]] = [:]
    }

    private func linkStateURL(in archivesBase: URL) -> URL {
        archivesBase.appendingPathComponent(".kiln-docc-dependencies.json")
    }

    func loadLinkState(_ archivesBase: URL) -> LinkState {
        guard let data = try? Data(contentsOf: linkStateURL(in: archivesBase)) else { return LinkState() }
        if let state = try? JSONDecoder().decode(LinkState.self, from: data) { return state }
        // Tolerate the earlier format (a bare repo → deps map) so an existing cache
        // keeps its graph instead of silently re-deriving it.
        if let legacy = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return LinkState(dependencies: legacy, linkInputs: [:])
        }
        return LinkState()
    }

    func saveLinkState(_ state: LinkState, in archivesBase: URL, log: Log) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: archivesBase, withIntermediateDirectories: true)
        do {
            try data.write(to: linkStateURL(in: archivesBase))
        } catch {
            log("⚠️  cross-module links: couldn't persist the cross-module build state (\(error))")
        }
    }

    /// Order packages so every package follows the hosted packages it depends on
    /// (Kahn's algorithm). Packages in a cycle — which SwiftPM shouldn't produce —
    /// or with unknown edges are appended in their original order, so ordering can
    /// never drop work.
    static func dependencyOrdered(
        _ packages: [APIPackage],
        dependencies: [String: Set<String>],
        log: Log
    ) -> [APIPackage] {
        let known = Set(packages.map(\.repo))
        var remaining = packages
        var ordered: [APIPackage] = []
        var placed: Set<String> = []

        while !remaining.isEmpty {
            let ready = remaining.filter { package in
                // Only edges among the packages being ordered constrain us.
                let deps = (dependencies[package.repo] ?? []).intersection(known)
                return deps.subtracting(placed).isEmpty
            }
            guard !ready.isEmpty else {
                // Cycle (or unresolvable edge): emit the rest in declaration order
                // rather than failing the build.
                log("⚠️  cross-module links: dependency cycle among \(remaining.map(\.repo).joined(separator: ", ")) — building in declared order")
                ordered.append(contentsOf: remaining)
                break
            }
            ordered.append(contentsOf: ready)
            let readyRepos = Set(ready.map(\.repo))
            placed.formUnion(readyRepos)
            remaining.removeAll { readyRepos.contains($0.repo) }
        }
        return ordered
    }

    // MARK: Steps

    /// Clone (or reuse) the repo and hard-check-out the latest of `ref`. Fetching
    /// the ref and detaching onto `FETCH_HEAD` means a reused checkout always picks
    /// up new commits on a branch (and works identically for a tag).
    private func checkoutRepo(_ repo: String, ref: String, into checkout: URL, log: Log) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: checkout.appendingPathComponent(".git").path) {
            try? fileManager.removeItem(at: checkout)
            try fileManager.createDirectory(at: checkout, withIntermediateDirectories: true)
            try git(["clone", "\(gitHost)/\(repo).git", "."], in: checkout, repo: repo, ref: ref, log: log)
        }
        try git(["fetch", "--force", "--tags", "origin", ref], in: checkout, repo: repo, ref: ref, log: log)
        try git(["checkout", "--force", "--detach", "FETCH_HEAD"], in: checkout, repo: repo, ref: ref, log: log)
    }

    // MARK: Cross-module dependencies

    /// The hosted packages a checkout depends on (transitively), as repo slugs.
    ///
    /// Reads SwiftPM's resolved dependency tree (`swift package show-dependencies`)
    /// and keeps only the packages this site actually hosts — those are the ones
    /// whose archives can resolve links. A failure here is non-fatal: the package
    /// simply builds without dependency archives (links stay unresolved, as before).
    func hostedDependencies(in checkout: URL, log: Log) -> Set<String> {
        guard let json = try? runCapturing("swift", ["package", "show-dependencies", "--format", "json"], in: checkout),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            log("⚠️  cross-module links: couldn't read dependencies of \(checkout.lastPathComponent)")
            return []
        }
        var urls: Set<String> = []
        Self.collectDependencyURLs(root, into: &urls)

        let hosted = Set(docc.packages.map { $0.repo.lowercased() })
        var found: Set<String> = []
        for url in urls {
            guard let slug = Self.repoSlug(fromURL: url), hosted.contains(slug) else { continue }
            // Map back to the configured casing.
            if let match = docc.packages.first(where: { $0.repo.lowercased() == slug }) {
                found.insert(match.repo)
            }
        }
        return found
    }

    /// Walk `show-dependencies` JSON, collecting every dependency `url`.
    private static func collectDependencyURLs(_ node: Any, into urls: inout Set<String>) {
        guard let object = node as? [String: Any] else { return }
        if let url = object["url"] as? String { urls.insert(url) }
        if let children = object["dependencies"] as? [Any] {
            for child in children { collectDependencyURLs(child, into: &urls) }
        }
    }

    /// Normalise a git URL to a lower-cased `owner/name` slug, matching
    /// ``APIPackage/repo`` (e.g. `https://github.com/vapor/sql-kit.git` →
    /// `vapor/sql-kit`). Returns `nil` for anything without two path components.
    static func repoSlug(fromURL url: String) -> String? {
        var trimmed = url
        if trimmed.hasSuffix(".git") { trimmed.removeLast(4) }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        var owner = parts[parts.count - 2]
        // SCP-style remotes (`git@github.com:owner/name`) fold the host into the
        // owner component; keep only what follows the colon.
        if let colon = owner.lastIndex(of: ":") { owner = String(owner[owner.index(after: colon)...]) }
        return "\(owner)/\(parts[parts.count - 1])".lowercased()
    }

    /// Archive paths to pass as `--dependency` when building `package`: the
    /// default-version archives of every hosted package it depends on that already
    /// exist on disk. Cross-links point at the canonical (default) version, which
    /// is what the site surfaces.
    private func existingDependencyArchives(
        for package: APIPackage,
        dependencies: [String: Set<String>],
        in archivesBase: URL
    ) -> [URL] {
        let fileManager = FileManager.default
        var archives: [URL] = []
        for repo in (dependencies[package.repo] ?? []).sorted() {
            guard let dependency = docc.packages.first(where: { $0.repo == repo }) else { continue }
            let version = dependency.defaultVersion
            for module in version.modules {
                let archive = DocCRenderPhase.archiveURL(module: module, version: version, in: archivesBase)
                if fileManager.fileExists(atPath: archive.path) { archives.append(archive) }
            }
        }
        return archives
    }

    /// Archives of the *other* modules this package ships in the same version, when
    /// they already exist (built earlier in this run, or cached). Modules within a
    /// package are built one target at a time, so a sibling's archive is what lets
    /// links between them resolve.
    private func existingSiblingArchives(
        of module: Module,
        in version: PackageVersion,
        package: APIPackage,
        archivesBase: URL
    ) -> [URL] {
        let fileManager = FileManager.default
        return version.modules
            .filter { $0.name != module.name }
            .map { DocCRenderPhase.archiveURL(module: $0, version: version, in: archivesBase) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// Inject the swift-docc-plugin into every Swift manifest variant that lacks
    /// it, so `swift package generate-documentation` is available. String-inserts
    /// after `dependencies: [` because `swift package add-dependency` can't target
    /// version-specific manifests (adapted from vapor/api-docs' generator script).
    private func ensurePluginAvailable(in checkout: URL, repo: String, log: Log) throws {
        let fileManager = FileManager.default
        let manifestNames = ["6.2", "6.1", "6.0", "5.10", "5.9", "5.8", "5.7"].map { "Package@swift-\($0).swift" } + ["Package.swift"]
        var foundAny = false
        for name in manifestNames {
            let url = checkout.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            foundAny = true
            var contents = try String(contentsOf: url, encoding: .utf8)
            guard !contents.contains("swift-docc-plugin") else { continue }
            guard let range = contents.range(of: "dependencies: [") else { continue }
            log("🧬 injecting swift-docc-plugin into \(name)")
            contents.insert(
                contentsOf: "\n        .package(url: \"https://github.com/apple/swift-docc-plugin.git\", from: \"1.4.0\"),",
                at: range.upperBound
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        guard foundAny else { throw BuildError.noManifest(repo: repo) }
    }

    /// Run `swift package generate-documentation` for one module, writing the raw
    /// `.doccarchive` (no static-hosting transform) to `archive`.
    private func generate(module: Module, package: APIPackage, version: PackageVersion,
                          checkout: URL, archive: URL, dependencyArchives: [URL] = [], log: Log) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: archive)
        try fileManager.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)

        // No DOCC_HTML_DIR / --transform-for-static-hosting → the output is the
        // archive Kiln reads. Indexing stays ON so `index/index.json` (the sidebar
        // nav) is produced.
        var args = [
            "package",
            "--allow-writing-to-directory", archive.deletingLastPathComponent().path,
            "generate-documentation",
            "--target", module.name,
            "--experimental-skip-synthesized-symbols",
            "--enable-inherited-docs",
            "--enable-experimental-overloaded-symbol-presentation",
            "--output-path", archive.path,
        ]
        if crossModuleLinks {
            // Emit link metadata so *this* archive can resolve links for its
            // dependents, and consume the dependencies' metadata for its own.
            args.append("--enable-experimental-external-link-support")
            for dependency in dependencyArchives {
                args.append(contentsOf: ["--dependency", dependency.path])
            }
            if !dependencyArchives.isEmpty {
                log("   ↳ resolving links against \(dependencyArchives.count) dependency archive(s)")
            }
        }
        let status = try run("swift", args, in: checkout, log: log)
        guard status == 0 else {
            throw BuildError.generateFailed(module: module.name, repo: package.repo, ref: version.ref, status: status)
        }
        guard fileManager.fileExists(atPath: archive.appendingPathComponent("metadata.json").path) else {
            throw BuildError.archiveNotProduced(module: module.name, at: archive.path)
        }
        try stripToKilnEssentials(archive)
    }

    /// Trim a generated `.doccarchive` to what Kiln reads: `metadata.json`, the
    /// render nodes (`data/`), the navigator index (`index/`), and the asset
    /// folders it copies (`images`/`videos`/`downloads`). Modern
    /// `generate-documentation` also bundles the swift-docc-render SPA
    /// (css/js/index.html/documentation/…) which Kiln never touches and which
    /// roughly triples the archive — pure dead weight in the (S3) cache.
    ///
    /// The external-link metadata (`linkable-entities.json`/`link-hierarchy.json`,
    /// written only under ``crossModuleLinks``) is kept: a *cached* archive is
    /// passed as a `--dependency` to its dependents on later builds, and without
    /// this metadata those links would silently stop resolving.
    private func stripToKilnEssentials(_ archive: URL) throws {
        let keep: Set<String> = [
            "metadata.json", "data", "index", "images", "videos", "downloads",
            "linkable-entities.json", "link-hierarchy.json",
        ]
        let fileManager = FileManager.default
        for entry in try fileManager.contentsOfDirectory(atPath: archive.path) where !keep.contains(entry) {
            try? fileManager.removeItem(at: archive.appendingPathComponent(entry))
        }
    }

    // MARK: Process

    private func git(_ args: [String], in directory: URL, repo: String, ref: String, log: Log) throws {
        let status = try run("git", args, in: directory, log: log)
        guard status == 0 else { throw BuildError.gitFailed(repo: repo, ref: ref, status: status) }
    }

    /// Run a tool via `/usr/bin/env`, streaming its output to the terminal, and
    /// return its exit status.
    private func run(_ tool: String, _ args: [String], in directory: URL, log: Log) throws -> Int32 {
        log("+ \(tool) \(args.joined(separator: " "))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Run a tool and capture its standard output (used for machine-readable
    /// queries like `swift package show-dependencies --format json`). Throws on a
    /// non-zero exit so callers can fall back.
    private func runCapturing(_ tool: String, _ args: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BuildError.generateFailed(module: tool, repo: directory.lastPathComponent,
                                            ref: "", status: process.terminationStatus)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func repoSlug(_ repo: String) -> String {
        repo.replacingOccurrences(of: "/", with: "-")
    }
}
