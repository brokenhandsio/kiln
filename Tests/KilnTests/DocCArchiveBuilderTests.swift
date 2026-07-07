import Testing
import Foundation
@testable import Kiln

@Suite("DocC archive builder")
struct DocCArchiveBuilderTests {
    @Test("Rebuild selects the right modules to force")
    func rebuildForces() {
        let jwtKit = Module("JWTKit")
        #expect(DocCArchiveBuilder.Rebuild.missing.forces(jwtKit) == false)
        #expect(DocCArchiveBuilder.Rebuild.all.forces(jwtKit) == true)
        // Matched case-insensitively (CLI passes lowercased names).
        #expect(DocCArchiveBuilder.Rebuild.modules(["jwtkit"]).forces(jwtKit) == true)
        #expect(DocCArchiveBuilder.Rebuild.modules(["queues"]).forces(jwtKit) == false)
    }

    @Test("Building archives for a site without DocC is a no-op")
    func noDocCNoOp() throws {
        let site = KilnSite(name: "Plain", url: "https://example.com")
        let built = try Kiln.buildDocCArchives(site, contentDirectory: FileManager.default.temporaryDirectory.path)
        #expect(built.isEmpty)
    }
}
