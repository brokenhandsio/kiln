import Testing
import Foundation
@testable import Kiln

@Suite("DocC URL scheme")
struct DocCURLsTests {
    private let defaultVersion = PackageVersion("v1", ref: "main", isDefault: true, modules: [])
    private let preVersion = PackageVersion("5-alpha", ref: "main", isPrerelease: true, modules: [])

    // MARK: DocCURLs

    @Test("Default-version pages strip the documentation/<module> prefix")
    func defaultVersionURLs() {
        let urls = DocCURLs(moduleName: "Queues", version: defaultVersion)
        #expect(urls.url(forDocCPath: "/documentation/queues") == "/queues/")
        #expect(urls.url(forDocCPath: "/documentation/queues/queue") == "/queues/queue/")
        #expect(urls.url(forDocCPath: "/documentation/queues/queue/dispatch(_:)-630ll") == "/queues/queue/dispatch(_:)-630ll/")
        #expect(urls.moduleRootURL == "/queues/")
        // An extension page under the module keeps its deeper path.
        #expect(urls.url(forDocCPath: "/documentation/queues/vapor/application") == "/queues/vapor/application/")
    }

    @Test("Non-default versions nest under the module")
    func versionedURLs() {
        let urls = DocCURLs(moduleName: "Queues", version: preVersion)
        #expect(urls.moduleRootURL == "/queues/5-alpha/")
        #expect(urls.url(forDocCPath: "/documentation/queues/queue") == "/queues/5-alpha/queue/")
    }

    @Test("basePath prefixes every URL")
    func basePathURLs() {
        let urls = DocCURLs(moduleName: "Queues", version: defaultVersion, basePath: "/docs")
        #expect(urls.url(forDocCPath: "/documentation/queues/queue") == "/docs/queues/queue/")
        #expect(urls.moduleRootURL == "/docs/queues/")
    }

    @Test("Output files use pretty (directory) paths")
    func outputFiles() {
        let out = URL(fileURLWithPath: "/out")
        let urls = DocCURLs(moduleName: "Queues", version: defaultVersion)
        #expect(urls.outputFile(forDocCPath: "/documentation/queues/queue", in: out).path == "/out/queues/queue/index.html")
        #expect(urls.outputFile(forDocCPath: "/documentation/queues", in: out).path == "/out/queues/index.html")

        let versioned = DocCURLs(moduleName: "Queues", version: preVersion)
        #expect(versioned.outputFile(forDocCPath: "/documentation/queues/queue", in: out).path == "/out/queues/5-alpha/queue/index.html")
        #expect(versioned.moduleDirectory(in: out).path == "/out/queues/5-alpha")
    }

    // MARK: Registry + cross-module mapper

    /// A two-package site: `vapor/queues` (Queues + XCTQueues, single version) and
    /// `vapor/vapor` (Vapor, default v4 + prerelease v5-alpha).
    private func site() -> DocCSite {
        let vapor = Module("Vapor")
        return DocCSite(packages: [
            APIPackage("vapor/queues", versions: [.single(ref: "main", modules: [Module("Queues"), Module("XCTQueues")])]),
            APIPackage("vapor/vapor", versions: [
                PackageVersion("4", ref: "vapor-4", isDefault: true, modules: [vapor]),
                PackageVersion("5-alpha", ref: "main", isPrerelease: true, modules: [vapor]),
            ]),
        ])
    }

    @Test("Registry knows which namespaces are hosted")
    func registryHosts() {
        let registry = DocCModuleRegistry(site: site())
        #expect(registry.hosts(namespace: "queues"))
        #expect(registry.hosts(namespace: "xctqueues"))
        #expect(registry.hosts(namespace: "vapor"))
        #expect(!registry.hosts(namespace: "foundation"))
        #expect(registry.catalogURL == "/")
    }

    @Test("Same-package links keep the current version; cross-package links use the target default")
    func crossModuleVersioning() {
        let registry = DocCModuleRegistry(site: site())

        // Rendering a Vapor page at the v5-alpha (non-default) version.
        let vaporPre = DocCURLs(moduleName: "Vapor", version: preVersion)
        let fromVaporPre = registry.linkMapper(current: vaporPre, currentPackageRepo: "vapor/vapor")
        // Same package (Vapor→Vapor) stays on 5-alpha.
        #expect(fromVaporPre("/documentation/vapor/application") == "/vapor/5-alpha/application/")
        // Different package (Vapor→Queues) drops to Queues' default version.
        #expect(fromVaporPre("/documentation/queues/queue") == "/queues/queue/")

        // Rendering a Queues page (default version).
        let queues = DocCURLs(moduleName: "Queues", version: PackageVersion("default", ref: "main", isDefault: true, modules: []))
        let fromQueues = registry.linkMapper(current: queues, currentPackageRepo: "vapor/queues")
        // Sibling module in the same package (Queues→XCTQueues), same (default) version.
        #expect(fromQueues("/documentation/xctqueues/foo") == "/xctqueues/foo/")
        // Cross-package to Vapor uses Vapor's default (v4 → no segment).
        #expect(fromQueues("/documentation/vapor/application") == "/vapor/application/")
    }

    @Test("Asset paths mount under the current module; unhosted and external pass sensibly")
    func assetAndExternalMapping() {
        let registry = DocCModuleRegistry(site: site())
        let queues = DocCURLs(moduleName: "Queues", version: PackageVersion("default", ref: "main", isDefault: true, modules: []))
        let map = registry.linkMapper(current: queues, currentPackageRepo: "vapor/queues")

        // Asset under the current module's root.
        #expect(map("/images/diagram.png") == "/queues/images/diagram.png")
        // Unhosted documentation path falls back to the raw path (not crash).
        #expect(map("/documentation/foundation/date") == "/documentation/foundation/date")
        // External + mailto pass through.
        #expect(map("https://swift.org") == "https://swift.org")
        #expect(map("mailto:core@vapor.codes") == "mailto:core@vapor.codes")
    }

    @Test("The mapper is usable as a DocCLinkResolver path mapper")
    func integratesWithResolver() {
        let registry = DocCModuleRegistry(site: site())
        let queues = DocCURLs(moduleName: "Queues", version: PackageVersion("default", ref: "main", isDefault: true, modules: []))
        let resolver = DocCLinkResolver(
            references: [
                "doc://Q/documentation/Queues/Queue": .topic(TopicReferenceFixture.make(
                    identifier: "doc://Q/documentation/Queues/Queue", title: "Queue",
                    url: "/documentation/queues/queue", kind: "symbol"))
            ],
            mapPath: registry.linkMapper(current: queues, currentPackageRepo: "vapor/queues")
        )
        let link = resolver.resolveTopic("doc://Q/documentation/Queues/Queue")
        #expect(link?.href == "/queues/queue/")
        #expect(link?.isSymbol == true)
    }
}

/// Builds a `TopicReference` from JSON (its init is decode-only).
enum TopicReferenceFixture {
    static func make(identifier: String, title: String, url: String, kind: String) -> TopicReference {
        let json = """
        {"type":"topic","identifier":"\(identifier)","title":"\(title)","url":"\(url)","kind":"\(kind)"}
        """
        return try! JSONDecoder().decode(TopicReference.self, from: Data(json.utf8))
    }
}
