import Testing
import Foundation
@testable import Kiln

@Suite("DocC archive builder")
struct DocCArchiveBuilderTests {
    @Test("Rebuild targets select the right package/version to force")
    func rebuildForces() {
        let routingKit = APIPackage("vapor/routing-kit", versions: [
            PackageVersion("4", ref: "v4", isDefault: true, modules: [Module("RoutingKit")]),
            PackageVersion("5-beta", ref: "main", isPrerelease: true, modules: [Module("RoutingKit")]),
        ])
        let v4 = routingKit.versions[0], main = routingKit.versions[1]
        let jwt = APIPackage("vapor/jwt", versions: [.single(ref: "main", modules: [Module("JWT")])])

        #expect(DocCArchiveBuilder.Rebuild.missing.forces(package: routingKit, version: v4) == false)
        #expect(DocCArchiveBuilder.Rebuild.all.forces(package: routingKit, version: v4) == true)

        // Bare repo (short or full) → all versions.
        let allVersions = DocCArchiveBuilder.Rebuild.rebuilding(["routing-kit"])
        #expect(allVersions.forces(package: routingKit, version: v4) == true)
        #expect(allVersions.forces(package: routingKit, version: main) == true)
        #expect(DocCArchiveBuilder.Rebuild.rebuilding(["vapor/routing-kit"]).forces(package: routingKit, version: v4) == true)
        #expect(allVersions.forces(package: jwt, version: jwt.versions[0]) == false)

        // repo@ref → only the version built from that ref.
        let onlyMain = DocCArchiveBuilder.Rebuild.rebuilding(["routing-kit@main"])
        #expect(onlyMain.forces(package: routingKit, version: main) == true)
        #expect(onlyMain.forces(package: routingKit, version: v4) == false)
    }

    @Test("Building archives for a site without DocC is a no-op")
    func noDocCNoOp() throws {
        let site = KilnSite(name: "Plain", url: "https://example.com")
        let built = try Kiln.buildDocCArchives(site, contentDirectory: FileManager.default.temporaryDirectory.path)
        #expect(built.isEmpty)
    }

    @Test("Git URLs normalise to owner/name repo slugs")
    func repoSlugFromURL() {
        #expect(DocCArchiveBuilder.repoSlug(fromURL: "https://github.com/vapor/sql-kit.git") == "vapor/sql-kit")
        #expect(DocCArchiveBuilder.repoSlug(fromURL: "https://github.com/vapor/sql-kit") == "vapor/sql-kit")
        #expect(DocCArchiveBuilder.repoSlug(fromURL: "git@github.com:vapor/SQL-Kit.git") == "vapor/sql-kit")
        #expect(DocCArchiveBuilder.repoSlug(fromURL: "https://github.com/vapor/sql-kit/") == "vapor/sql-kit")
        #expect(DocCArchiveBuilder.repoSlug(fromURL: "sql-kit") == nil)
    }

    /// Build order must place a package after everything it depends on, so each
    /// dependency's archive exists to be passed as `--dependency`.
    @Test("Packages are built in dependency order")
    func dependencyOrdering() {
        func pkg(_ repo: String) -> APIPackage {
            APIPackage(repo, versions: [.single(ref: "main", modules: [Module(repo)])])
        }
        // fluent-kit → sql-kit → nio (declared in the "wrong" order on purpose).
        let packages = [pkg("vapor/fluent-kit"), pkg("vapor/sql-kit"), pkg("apple/swift-nio")]
        let deps: [String: Set<String>] = [
            "vapor/fluent-kit": ["vapor/sql-kit", "apple/swift-nio"],
            "vapor/sql-kit": ["apple/swift-nio"],
            "apple/swift-nio": [],
        ]
        let ordered = DocCArchiveBuilder.dependencyOrdered(packages, dependencies: deps, log: { _ in }).map(\.repo)
        #expect(ordered.firstIndex(of: "apple/swift-nio")! < ordered.firstIndex(of: "vapor/sql-kit")!)
        #expect(ordered.firstIndex(of: "vapor/sql-kit")! < ordered.firstIndex(of: "vapor/fluent-kit")!)
        #expect(ordered.count == 3)
    }

    /// Within a package, a module must be built after the sibling modules it
    /// depends on, so their archives exist to resolve links against.
    @Test("Modules are ordered after the siblings they depend on")
    func moduleOrdering() {
        let modules = [Module("XCTFluent"), Module("FluentSQL"), Module("FluentKit")]  // "wrong" order
        // Target deps as `swift package describe` reports them.
        let deps: [String: Set<String>] = [
            "XCTFluent": ["FluentKit"],
            "FluentSQL": ["FluentKit"],
            "FluentKit": [],
        ]
        let ordered = DocCArchiveBuilder.topologicallyOrdered(modules, key: \.name,
                                                              dependencies: deps, subject: "module", log: { _ in })
            .map(\.name)
        #expect(ordered.first == "FluentKit")
        #expect(ordered.firstIndex(of: "FluentKit")! < ordered.firstIndex(of: "FluentSQL")!)
        #expect(ordered.firstIndex(of: "FluentKit")! < ordered.firstIndex(of: "XCTFluent")!)
    }

    @Test("Unknown edges don't stall ordering, and cycles still build everything")
    func orderingEdgeCases() {
        func pkg(_ repo: String) -> APIPackage {
            APIPackage(repo, versions: [.single(ref: "main", modules: [Module(repo)])])
        }
        // A dependency that isn't among the ordered packages must not stall it.
        let cached = DocCArchiveBuilder.dependencyOrdered(
            [pkg("vapor/vapor")],
            dependencies: ["vapor/vapor": ["vapor/routing-kit"]],
            log: { _ in }
        ).map(\.repo)
        #expect(cached == ["vapor/vapor"])

        // A cycle can't happen in SwiftPM, but must never drop work if it did.
        let cyclic = DocCArchiveBuilder.dependencyOrdered(
            [pkg("a/one"), pkg("b/two")],
            dependencies: ["a/one": ["b/two"], "b/two": ["a/one"]],
            log: { _ in }
        ).map(\.repo)
        #expect(Set(cyclic) == ["a/one", "b/two"])
    }

    /// Cache invalidation: a cached archive must be rebuilt when it predates
    /// cross-module linking, or when a dependency has been rebuilt since — otherwise
    /// CI keeps serving archives whose cross-module links are absent or stale.
    @Test("Archives are invalidated by missing link metadata and by newer dependencies")
    func cacheInvalidation() throws {
        let fm = FileManager.default
        let sqlKit = APIPackage("vapor/sql-kit", versions: [.single(ref: "main", modules: [Module("SQLKit")])])
        let fluent = APIPackage("vapor/fluent-kit", versions: [.single(ref: "main", modules: [Module("FluentKit")])])
        let docc = DocCSite(packages: [sqlKit, fluent])

        let content = fm.temporaryDirectory.appendingPathComponent("kiln-inval-\(UUID().uuidString)")
        let archivesBase = content.appendingPathComponent("archives")
        defer { try? fm.removeItem(at: content) }

        // Stage two archives, both carrying link metadata.
        func stage(_ package: APIPackage) throws -> URL {
            let version = package.versions[0]
            let archive = DocCRenderPhase.archiveURL(module: version.modules[0], version: version, in: archivesBase)
            try fm.createDirectory(at: archive, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: archive.appendingPathComponent("linkable-entities.json"))
            try Data("{}".utf8).write(to: archive.appendingPathComponent("metadata.json"))
            return archive
        }
        let sqlArchive = try stage(sqlKit)
        let fluentArchive = try stage(fluent)

        let builder = DocCArchiveBuilder(docc: docc, contentDirectory: content,
                                         checkoutDirectory: content, crossModuleLinks: true)
        let deps: [String: Set<String>] = ["vapor/fluent-kit": ["vapor/sql-kit"]]

        // Both have metadata → neither is invalidated on that basis.
        #expect(builder.lacksLinkMetadata(fluentArchive) == false)

        // Baseline: what FluentKit's links were resolved against.
        let baseline = builder.currentLinkInputs(for: fluent, version: fluent.defaultVersion, autoGraph: deps, archivesBase: archivesBase, log: { _ in })
        #expect(baseline.count == 1)
        #expect(builder.linkInputsChanged(recorded: baseline, current: baseline) == false)

        // Merely re-timestamping a dependency must NOT invalidate — a CI cache
        // restore does exactly this, and rebuilding everything would defeat it.
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 9_999_999)],
                             ofItemAtPath: sqlArchive.appendingPathComponent("linkable-entities.json").path)
        let afterTouch = builder.currentLinkInputs(for: fluent, version: fluent.defaultVersion, autoGraph: deps, archivesBase: archivesBase, log: { _ in })
        #expect(builder.linkInputsChanged(recorded: baseline, current: afterTouch) == false)

        // Changing the dependency's link *surface* does invalidate.
        try Data("{\"symbols\":[\"new\"]}".utf8)
            .write(to: sqlArchive.appendingPathComponent("linkable-entities.json"))
        let afterChange = builder.currentLinkInputs(for: fluent, version: fluent.defaultVersion, autoGraph: deps, archivesBase: archivesBase, log: { _ in })
        #expect(builder.linkInputsChanged(recorded: baseline, current: afterChange) == true)

        // A package with no dependencies is never invalidated this way, and an
        // archive with no recorded baseline isn't either (it adopts one instead).
        let none = builder.currentLinkInputs(for: sqlKit, version: sqlKit.defaultVersion, autoGraph: deps, archivesBase: archivesBase, log: { _ in })
        #expect(none.isEmpty)
        #expect(builder.linkInputsChanged(recorded: nil, current: afterChange) == false)

        // An archive built before the feature has no link metadata → rebuild.
        try fm.removeItem(at: fluentArchive.appendingPathComponent("linkable-entities.json"))
        #expect(builder.lacksLinkMetadata(fluentArchive) == true)
    }

    /// Explicit pins drive which dependency versions Stage A passes; unknown pins
    /// are skipped, and un-pinned versions fall back to the auto graph.
    @Test("Explicit dependency pins select the pinned versions; auto is the fallback")
    func explicitDependencyPins() {
        let routingKit = APIPackage("vapor/routing-kit", versions: [
            PackageVersion("4", ref: "v4", isDefault: true, modules: [Module("RoutingKit")]),
            PackageVersion("5-beta", ref: "main", isPrerelease: true, modules: [Module("RoutingKit")]),
        ])
        let sqlKit = APIPackage("vapor/sql-kit", versions: [.single(ref: "main", modules: [Module("SQLKit")])])
        let vapor = APIPackage("vapor/vapor", versions: [
            // Pinned version.
            PackageVersion("5-beta", ref: "main", isPrerelease: true, dependencies: [
                DependencyPin("vapor/routing-kit", "5-beta"),
                DependencyPin("vapor/sql-kit"),
                DependencyPin("vapor/not-hosted"),          // skipped with a warning
                DependencyPin("vapor/routing-kit", "9"),    // no such version → skipped
            ], modules: [Module("Vapor")]),
            // Un-pinned version → auto graph applies.
            PackageVersion("4", ref: "vapor4", isDefault: true, modules: [Module("Vapor")]),
        ])
        let builder = DocCArchiveBuilder(
            docc: DocCSite(packages: [routingKit, sqlKit, vapor]),
            contentDirectory: URL(fileURLWithPath: "/tmp"), checkoutDirectory: URL(fileURLWithPath: "/tmp"),
            crossModuleLinks: true)
        let auto: [String: Set<String>] = ["vapor/vapor": ["vapor/routing-kit"]]

        // Pinned version: routing-kit@5-beta + sql-kit@default; bad pins dropped.
        let pinned = builder.linkDependencies(for: vapor, version: vapor.versions[0], autoGraph: auto, log: { _ in })
            .map { "\($0.package.repo)@\($0.version.id)" }
        #expect(pinned == ["vapor/routing-kit@5-beta", "vapor/sql-kit@default"])

        // Un-pinned version: falls back to the auto graph, matched by line (4).
        let autoResolved = builder.linkDependencies(for: vapor, version: vapor.versions[1], autoGraph: auto, log: { _ in })
            .map { "\($0.package.repo)@\($0.version.id)" }
        #expect(autoResolved == ["vapor/routing-kit@4"])

        // Ordering edges union pins (5-beta) + auto (4) → routing-kit + sql-kit.
        var edges: Set<String> = []
        for version in vapor.versions { edges.formUnion(builder.linkDependencyRepos(for: vapor, version: version, autoGraph: auto)) }
        #expect(edges == ["vapor/routing-kit", "vapor/sql-kit"])
    }

    /// Stage A must pass the dependency archive on the *same* major line as the
    /// version being built, so a 5-line build resolves links against 5-line deps.
    @Test("Dependency version selection matches the building major line")
    func dependencyVersionSelection() {
        let sqlKit = APIPackage("vapor/sql-kit", versions: [
            PackageVersion("4", ref: "v4", isDefault: true, modules: [Module("SQLKit")]),
            PackageVersion("5-beta", ref: "main", isPrerelease: true, modules: [Module("SQLKit")]),
        ])
        let asyncKit = APIPackage("vapor/async-kit", versions: [.single(ref: "main", modules: [Module("AsyncKit")])])
        let builder = DocCArchiveBuilder(
            docc: DocCSite(packages: [sqlKit, asyncKit]),
            contentDirectory: URL(fileURLWithPath: "/tmp"), checkoutDirectory: URL(fileURLWithPath: "/tmp"),
            crossModuleLinks: true)

        // Building a line-5 dependent → SQLKit's 5-beta line.
        #expect(builder.dependencyVersion(of: sqlKit, forLine: 5).id == "5-beta")
        // Building a line-4 dependent → SQLKit's 4 line (its default).
        #expect(builder.dependencyVersion(of: sqlKit, forLine: 4).id == "4")
        // No line info, or a line the dependency doesn't have → its default.
        #expect(builder.dependencyVersion(of: sqlKit, forLine: nil).id == "4")
        #expect(builder.dependencyVersion(of: sqlKit, forLine: 6).id == "4")
        // A single-version dependency always resolves to its lone default.
        #expect(builder.dependencyVersion(of: asyncKit, forLine: 5).isDefault)
    }

    /// The state is cached beside the archives so a later build knows the edges of
    /// packages it never checks out (and CI's archive cache carries it along).
    @Test("Cross-module build state round-trips, and the earlier format still loads")
    func linkStatePersistence() throws {
        let site = KilnSite(name: "API", url: "https://api.example.com", docc: DocCSite(packages: [
            APIPackage("vapor/fluent-kit", versions: [.single(ref: "main", modules: [Module("FluentKit")])]),
        ]))
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-deps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let builder = DocCArchiveBuilder(docc: site.docc!, contentDirectory: base,
                                         checkoutDirectory: base, crossModuleLinks: true)
        #expect(builder.loadLinkState(base).dependencies.isEmpty)   // nothing cached yet

        var state = DocCArchiveBuilder.LinkState()
        state.dependencies = ["vapor/fluent-kit": ["apple/swift-nio", "vapor/sql-kit"]]
        state.linkInputs = ["default/FluentKit.doccarchive": ["default/SQLKit.doccarchive": "abc123"]]
        builder.saveLinkState(state, in: base, log: { _ in })

        let loaded = builder.loadLinkState(base)
        #expect(loaded.dependencies == state.dependencies)
        #expect(loaded.linkInputs == state.linkInputs)

        // An existing cache written in the earlier (bare graph) format still loads,
        // so enabling this doesn't throw away a populated dependency graph.
        try Data("{\"a/one\":[\"b/two\"]}".utf8)
            .write(to: base.appendingPathComponent(".kiln-docc-dependencies.json"))
        #expect(builder.loadLinkState(base).dependencies == ["a/one": ["b/two"]])
    }

    @Test("A stale Package.resolved is dropped, a tracked one is kept")
    func staleResolutionCleanup() throws {
        let fm = FileManager.default
        let site = DocCSite(packages: [
            APIPackage("vapor/vapor", versions: [.single(ref: "main", modules: [Module("Vapor")])]),
        ])
        let base = fm.temporaryDirectory.appendingPathComponent("kiln-resolved-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let builder = DocCArchiveBuilder(docc: site, contentDirectory: base, checkoutDirectory: base)

        func git(_ args: [String], in directory: URL) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + args
            process.currentDirectoryURL = directory
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }

        /// A checkout holding a `Package.resolved`, optionally staged into the index.
        func checkout(named name: String, tracked: Bool) throws -> URL {
            let directory = base.appendingPathComponent(name)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try git(["init"], in: directory)
            try Data("{}".utf8).write(to: directory.appendingPathComponent("Package.resolved"))
            if tracked { try git(["add", "Package.resolved"], in: directory) }
            return directory
        }

        /// Hoisted out of `#expect` — the macro can't capture a `@Sendable` closure.
        func clean(_ directory: URL) -> Bool {
            builder.removeStaleResolution(in: directory, repo: "vapor/vapor", ref: "vapor4", log: { _ in })
        }

        // Untracked: left over from another ref's build, so it goes.
        let stale = try checkout(named: "stale", tracked: false)
        #expect(clean(stale))
        #expect(fm.fileExists(atPath: stale.appendingPathComponent("Package.resolved").path) == false)

        // Tracked: `git checkout` already restored the right one for this ref.
        let pinned = try checkout(named: "pinned", tracked: true)
        #expect(clean(pinned) == false)
        #expect(fm.fileExists(atPath: pinned.appendingPathComponent("Package.resolved").path))

        // Nothing to clean up when the file was never there.
        let untouched = base.appendingPathComponent("untouched")
        try fm.createDirectory(at: untouched, withIntermediateDirectories: true)
        #expect(clean(untouched) == false)
    }
}
