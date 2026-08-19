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
    /// `vapor/vapor` (Vapor in both versions; VaporExtras only in the v5-alpha
    /// pre-release, so it's surfaced there).
    private func site() -> DocCSite {
        let vapor = Module("Vapor")
        return DocCSite(packages: [
            APIPackage("vapor/queues", versions: [.single(ref: "main", modules: [Module("Queues"), Module("XCTQueues")])]),
            APIPackage("vapor/vapor", versions: [
                PackageVersion("4", ref: "vapor-4", isDefault: true, modules: [vapor]),
                PackageVersion("5-alpha", ref: "main", isPrerelease: true, modules: [vapor, Module("VaporExtras")]),
            ]),
        ])
    }

    @Test("Registry knows which namespaces are hosted")
    func registryHosts() {
        let registry = DocCModuleRegistry(site: site())
        #expect(registry.hosts(namespace: "queues"))
        #expect(registry.hosts(namespace: "xctqueues"))
        #expect(registry.hosts(namespace: "vapor"))
        #expect(registry.hosts(namespace: "vaporextras")) // pre-release-only, still hosted
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
        // Cross-package to a pre-release-only module lands on its surfaced version.
        #expect(fromQueues("/documentation/vaporextras/thing") == "/vaporextras/5-alpha/thing/")
    }

    @Test("A version id's major line is its leading integer, or nil when it has none")
    func versionLineParsing() {
        #expect(DocCModuleRegistry.versionLine("4") == 4)
        #expect(DocCModuleRegistry.versionLine("5-beta") == 5)
        #expect(DocCModuleRegistry.versionLine("5-alpha") == 5)
        #expect(DocCModuleRegistry.versionLine("6-rc.1") == 6)
        #expect(DocCModuleRegistry.versionLine("10") == 10)
        #expect(DocCModuleRegistry.versionLine("default") == nil)
        #expect(DocCModuleRegistry.versionLine("main") == nil)
        #expect(DocCModuleRegistry.versionLine("") == nil)
    }

    @Test("A version's major line comes from an explicit line, else the id, else the name")
    func majorLineResolution() {
        // Conventional ids parse directly.
        #expect(PackageVersion("5-beta", ref: "main", modules: []).majorLine == 5)
        #expect(PackageVersion("4", ref: "v4", isDefault: true, modules: []).majorLine == 4)
        // A single-version package's synthetic "default" has no line.
        #expect(PackageVersion.single(ref: "main", modules: []).majorLine == nil)
        // A main-branch version whose id doesn't encode the major falls back to the
        // display name ("5.0 (beta)" → 5) — the Vapor `vapor@main` case.
        #expect(PackageVersion("latest", name: "5.0 (beta)", ref: "main", modules: []).majorLine == 5)
        // …or an explicit line wins over everything, for when neither id nor name helps.
        #expect(PackageVersion("edge", name: "Edge", ref: "main", line: 5, modules: []).majorLine == 5)
        #expect(PackageVersion("5-beta", ref: "main", line: 4, modules: []).majorLine == 4)  // pinned to 4
    }

    @Test("Cross-package links prefer the target's matching major line")
    func crossModuleLineMatching() {
        // Two multi-version packages, each with a 4 (default) and a 5 line.
        let site = DocCSite(packages: [
            APIPackage("me/a", versions: [
                PackageVersion("4", ref: "v4", isDefault: true, modules: [Module("AKit")]),
                PackageVersion("5-beta", ref: "main", isPrerelease: true, modules: [Module("AKit")]),
            ]),
            APIPackage("me/b", versions: [
                PackageVersion("4", ref: "v4", isDefault: true, modules: [Module("BKit")]),
                PackageVersion("5-alpha", ref: "main", isPrerelease: true, modules: [Module("BKit")]),
            ]),
        ])
        let registry = DocCModuleRegistry(site: site)

        // AKit @ 5-beta (line 5) → BKit should land on B's line-5 (5-alpha), not v4.
        let a5 = registry.linkMapper(current: DocCURLs(moduleName: "AKit",
            version: PackageVersion("5-beta", ref: "main", isPrerelease: true, modules: [])),
            currentPackageRepo: "me/a")
        #expect(a5("/documentation/bkit/thing") == "/bkit/5-alpha/thing/")

        // AKit @ 4 (default, line 4) → BKit's line-4 = its default (no segment).
        let a4 = registry.linkMapper(current: DocCURLs(moduleName: "AKit",
            version: PackageVersion("4", ref: "v4", isDefault: true, modules: [])),
            currentPackageRepo: "me/a")
        #expect(a4("/documentation/bkit/thing") == "/bkit/thing/")
    }

    @Test("An explicit dependency pin routes links to the pinned version, overriding line-matching")
    func explicitPinRouting() {
        // Vapor 5 pins routing-kit to `5-beta`, but sql-kit (single-version) to its
        // default, and doesn't pin console-kit at all.
        let site = DocCSite(packages: [
            APIPackage("vapor/vapor", versions: [
                PackageVersion("4", name: "4.x", ref: "vapor4", isDefault: true, dependencies: [
                    DependencyPin("vapor/routing-kit", "4"),
                    DependencyPin("vapor/sql-kit"),
                ], modules: [Module("Vapor")]),
                PackageVersion("5-beta", name: "5.0 (beta)", ref: "main", isPrerelease: true, dependencies: [
                    DependencyPin("vapor/routing-kit", "5-beta"),
                    DependencyPin("vapor/sql-kit"),
                ], modules: [Module("Vapor")]),
            ]),
            APIPackage("vapor/routing-kit", versions: [
                PackageVersion("4", name: "4.x", ref: "v4", isDefault: true, modules: [Module("RoutingKit")]),
                PackageVersion("5-beta", name: "5.0 (beta)", ref: "main", isPrerelease: true, modules: [Module("RoutingKit")]),
            ]),
            APIPackage("vapor/sql-kit", versions: [.single(ref: "main", modules: [Module("SQLKit")])]),
        ])
        let registry = DocCModuleRegistry(site: site)

        let vapor5 = registry.linkMapper(current: DocCURLs(moduleName: "Vapor",
            version: PackageVersion("5-beta", name: "5.0 (beta)", ref: "main", isPrerelease: true, modules: [])),
            currentPackageRepo: "vapor/vapor")
        // Pinned to routing-kit 5-beta.
        #expect(vapor5("/documentation/routingkit/trierouter") == "/routingkit/5-beta/trierouter/")
        // Pinned to single-version sql-kit's default.
        #expect(vapor5("/documentation/sqlkit/sqlquery") == "/sqlkit/sqlquery/")

        let vapor4 = registry.linkMapper(current: DocCURLs(moduleName: "Vapor",
            version: PackageVersion("4", name: "4.x", ref: "vapor4", isDefault: true, modules: [])),
            currentPackageRepo: "vapor/vapor")
        // Same-line pin, but explicit: routing-kit 4 (default → no segment).
        #expect(vapor4("/documentation/routingkit/trierouter") == "/routingkit/trierouter/")
    }

    @Test("A main-branch version routes by its resolved line, not its ref (the vapor@main case)")
    func mainBranchVersionRouting() {
        // Vapor gains a `main` line whose id doesn't encode the major; the display
        // name supplies it. RoutingKit is a conventional 4/5-beta package.
        let site = DocCSite(packages: [
            APIPackage("vapor/vapor", versions: [
                PackageVersion("4", name: "4.x", ref: "vapor4", isDefault: true, modules: [Module("Vapor")]),
                PackageVersion("main", name: "5.0 (beta)", ref: "main", isPrerelease: true, modules: [Module("Vapor")]),
            ]),
            APIPackage("vapor/routing-kit", versions: [
                PackageVersion("4", name: "4.x", ref: "v4", isDefault: true, modules: [Module("RoutingKit")]),
                PackageVersion("5-beta", name: "5.0 (beta)", ref: "main", isPrerelease: true, modules: [Module("RoutingKit")]),
            ]),
        ])
        let registry = DocCModuleRegistry(site: site)

        // Vapor's `main` version (line 5 via its name) → RoutingKit 5-beta, despite
        // the `main` ref carrying no version number.
        let vaporMain = registry.linkMapper(current: DocCURLs(moduleName: "Vapor",
            version: PackageVersion("main", name: "5.0 (beta)", ref: "main", isPrerelease: true, modules: [])),
            currentPackageRepo: "vapor/vapor")
        #expect(vaporMain("/documentation/routingkit/trierouter") == "/routingkit/5-beta/trierouter/")

        // Vapor 4 → RoutingKit 4 (default).
        let vapor4 = registry.linkMapper(current: DocCURLs(moduleName: "Vapor",
            version: PackageVersion("4", name: "4.x", ref: "vapor4", isDefault: true, modules: [])),
            currentPackageRepo: "vapor/vapor")
        #expect(vapor4("/documentation/routingkit/trierouter") == "/routingkit/trierouter/")
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
