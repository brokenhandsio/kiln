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
        func pkg(_ repo: String) -> (package: APIPackage, work: [(version: PackageVersion, modules: [Module])]) {
            let p = APIPackage(repo, versions: [.single(ref: "main", modules: [Module(repo)])])
            return (p, [(p.versions[0], p.versions[0].modules)])
        }
        // fluent-kit → sql-kit → nio (declared in the "wrong" order on purpose).
        let pending = [pkg("vapor/fluent-kit"), pkg("vapor/sql-kit"), pkg("apple/swift-nio")]
        let deps: [String: Set<String>] = [
            "vapor/fluent-kit": ["vapor/sql-kit", "apple/swift-nio"],
            "vapor/sql-kit": ["apple/swift-nio"],
            "apple/swift-nio": [],
        ]
        let ordered = DocCArchiveBuilder.dependencyOrdered(pending, dependencies: deps, log: { _ in })
            .map(\.package.repo)
        #expect(ordered.firstIndex(of: "apple/swift-nio")! < ordered.firstIndex(of: "vapor/sql-kit")!)
        #expect(ordered.firstIndex(of: "vapor/sql-kit")! < ordered.firstIndex(of: "vapor/fluent-kit")!)
        #expect(ordered.count == 3)
    }

    @Test("Dependencies outside the build set don't constrain the order, and cycles still build")
    func orderingEdgeCases() {
        func pkg(_ repo: String) -> (package: APIPackage, work: [(version: PackageVersion, modules: [Module])]) {
            let p = APIPackage(repo, versions: [.single(ref: "main", modules: [Module(repo)])])
            return (p, [(p.versions[0], p.versions[0].modules)])
        }
        // `vapor/vapor` depends on a package that isn't being rebuilt (already
        // cached) — that must not stall it.
        let cached = DocCArchiveBuilder.dependencyOrdered(
            [pkg("vapor/vapor")],
            dependencies: ["vapor/vapor": ["vapor/routing-kit"]],
            log: { _ in }
        ).map(\.package.repo)
        #expect(cached == ["vapor/vapor"])

        // A cycle can't happen in SwiftPM, but must never drop work if it did.
        let cyclic = DocCArchiveBuilder.dependencyOrdered(
            [pkg("a/one"), pkg("b/two")],
            dependencies: ["a/one": ["b/two"], "b/two": ["a/one"]],
            log: { _ in }
        ).map(\.package.repo)
        #expect(Set(cyclic) == ["a/one", "b/two"])
    }
}
