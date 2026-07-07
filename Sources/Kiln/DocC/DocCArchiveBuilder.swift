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

    init(
        docc: DocCSite,
        contentDirectory: URL,
        checkoutDirectory: URL,
        gitHost: String = "https://github.com"
    ) {
        self.docc = docc
        self.contentDirectory = contentDirectory
        self.checkoutDirectory = checkoutDirectory
        self.gitHost = gitHost
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

        var built: [String] = []
        for package in docc.packages {
            // Which (version, module) pairs actually need generating?
            var work: [(version: PackageVersion, modules: [Module])] = []
            for version in package.versions {
                let forced = rebuild.forces(package: package, version: version)
                let modules = package.modules.filter { module in
                    let archive = DocCRenderPhase.archiveURL(module: module, version: version, in: archivesBase)
                    return forced || !fileManager.fileExists(atPath: archive.path)
                }
                if !modules.isEmpty { work.append((version, modules)) }
            }
            guard !work.isEmpty else { continue }

            let checkout = checkoutDirectory.appendingPathComponent(repoSlug(package.repo))
            for (version, modules) in work {
                log("📦 \(package.repo) @ \(version.ref) → \(modules.map(\.name).joined(separator: ", "))")
                try checkoutRepo(package.repo, ref: version.ref, into: checkout, log: log)
                try ensurePluginAvailable(in: checkout, repo: package.repo, log: log)
                for module in modules {
                    let archive = DocCRenderPhase.archiveURL(module: module, version: version, in: archivesBase)
                    try generate(module: module, package: package, version: version,
                                 checkout: checkout, archive: archive, log: log)
                    built.append(module.name)
                }
            }
        }
        return built
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
                          checkout: URL, archive: URL, log: Log) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: archive)
        try fileManager.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)

        // No DOCC_HTML_DIR / --transform-for-static-hosting → the output is the
        // archive Kiln reads. Indexing stays ON so `index/index.json` (the sidebar
        // nav) is produced.
        let args = [
            "package",
            "--allow-writing-to-directory", archive.deletingLastPathComponent().path,
            "generate-documentation",
            "--target", module.name,
            "--experimental-skip-synthesized-symbols",
            "--enable-inherited-docs",
            "--enable-experimental-overloaded-symbol-presentation",
            "--output-path", archive.path,
        ]
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
    private func stripToKilnEssentials(_ archive: URL) throws {
        let keep: Set<String> = ["metadata.json", "data", "index", "images", "videos", "downloads"]
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

    private func repoSlug(_ repo: String) -> String {
        repo.replacingOccurrences(of: "/", with: "-")
    }
}
