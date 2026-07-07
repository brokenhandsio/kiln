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
}
