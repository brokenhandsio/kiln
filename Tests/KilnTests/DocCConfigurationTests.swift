import Testing
@testable import Kiln

@Suite("DocC configuration")
struct DocCConfigurationTests {
    /// A representative multi-package config used across the happy-path tests.
    private func sampleSite() -> DocCSite {
        let vapor = Module("Vapor", group: "Core", description: "Core web framework")
        let xctVapor = Module("XCTVapor", group: "Testing")
        return DocCSite(
            packages: [
                APIPackage(
                    "vapor/vapor",
                    versions: [
                        PackageVersion("4", name: "4.x", ref: "vapor-4", isDefault: true, modules: [vapor, xctVapor]),
                        PackageVersion("5-alpha", name: "5.0 (alpha)", ref: "main", isPrerelease: true, modules: [vapor, xctVapor]),
                    ]
                ),
                APIPackage("vapor/leaf-kit", group: "Templating",
                           versions: [.single(ref: "main", modules: [Module("LeafKit")])]),
            ],
            groupOrder: ["Core", "Templating", "Testing"]
        )
    }

    @Test("A well-formed DocC site validates")
    func validConfig() throws {
        let site = KilnSite(name: "API", url: "https://api.vapor.codes", docc: sampleSite())
        try site.validate()
        #expect(site.docc?.packages.count == 2)
        #expect(site.docc?.allModules.count == 3)
    }

    @Test("Valid dependency pins pass validation; bad ones are rejected with a clear error")
    func dependencyPinValidation() throws {
        func site(_ pins: [DependencyPin]) -> KilnSite {
            KilnSite(name: "API", url: "https://api.example.com", docc: DocCSite(packages: [
                APIPackage("vapor/vapor", versions: [
                    PackageVersion("5-beta", ref: "main", isDefault: true, dependencies: pins, modules: [Module("Vapor")]),
                ]),
                APIPackage("vapor/routing-kit", versions: [
                    PackageVersion("4", ref: "v4", isDefault: true, modules: [Module("RoutingKit")]),
                    PackageVersion("5-beta", ref: "main", isPrerelease: true, modules: [Module("RoutingKit")]),
                ]),
                APIPackage("vapor/sql-kit", versions: [.single(ref: "main", modules: [Module("SQLKit")])]),
            ]))
        }
        // Valid: hosted package + existing version id, and a version-less pin.
        try site([DependencyPin("vapor/routing-kit", "5-beta"), DependencyPin("vapor/sql-kit")]).validate()

        // Unknown package.
        #expect(throws: DocCConfigurationError.self) { try site([DependencyPin("vapor/not-hosted")]).validate() }
        // Unknown version of a hosted package.
        #expect(throws: DocCConfigurationError.self) { try site([DependencyPin("vapor/routing-kit", "9")]).validate() }
        // Pinning itself.
        #expect(throws: DocCConfigurationError.self) { try site([DependencyPin("vapor/vapor", "5-beta")]).validate() }
    }

    @Test("Single-version shorthand synthesises one default version")
    func shorthandDefaultVersion() {
        let package = APIPackage("vapor/leaf-kit", versions: [.single(ref: "main", modules: [Module("LeafKit")])])
        #expect(package.versions.count == 1)
        #expect(package.defaultVersion.isDefault)
        #expect(package.defaultVersion.ref == "main")
        #expect(package.defaultVersion.urlSegment == "")
    }

    @Test("Versions can ship different module sets")
    func perVersionModules() throws {
        let consoleKit = Module("ConsoleKit")
        let consoleLogger = Module("ConsoleLogger")
        let package = APIPackage("vapor/console-kit", group: "Core",
            versions: [
                PackageVersion("4", ref: "v4", isDefault: true, modules: [consoleKit]),
                PackageVersion("5-beta", ref: "main", isPrerelease: true, modules: [consoleKit, consoleLogger]),
            ])
        let v4 = package.versions[0], beta = package.versions[1]

        // v4 ships [ConsoleKit]; the beta adds ConsoleLogger.
        #expect(v4.modules.map(\.name) == ["ConsoleKit"])
        #expect(beta.modules.map(\.name) == ["ConsoleKit", "ConsoleLogger"])
        #expect(package.defaultModules.map(\.name) == ["ConsoleKit"])

        // Distinct modules pair with the versions that emit them.
        let across = package.modulesAcrossVersions
        #expect(across.map(\.module.name) == ["ConsoleKit", "ConsoleLogger"])
        #expect(across[0].versions.map(\.id) == ["4", "5-beta"])   // ConsoleKit in both
        #expect(across[1].versions.map(\.id) == ["5-beta"])         // ConsoleLogger beta-only

        // Surfaced version: ConsoleKit at its default (v4); ConsoleLogger, absent
        // from the default, at the beta so it stays discoverable.
        let surfaced = package.surfacedModules
        #expect(surfaced.map(\.module.name) == ["ConsoleKit", "ConsoleLogger"])
        #expect(surfaced.map(\.version.id) == ["4", "5-beta"])

        // The catalog/switcher list every surfaced module (beta-only included);
        // the same module name across versions is one module, so validation passes.
        let site = DocCSite(packages: [package])
        #expect(site.allModules.map(\.module.name) == ["ConsoleKit", "ConsoleLogger"])
        try site.validate()
    }

    @Test("Pre-release badge is inferred from id/name and overridable")
    func prereleaseBadge() {
        func version(_ id: String, name: String? = nil, prerelease: Bool = true, label: String? = nil) -> PackageVersion {
            PackageVersion(id, name: name, ref: "main", isPrerelease: prerelease, prereleaseLabel: label, modules: [])
        }
        // Inferred from the id …
        #expect(version("5-alpha").badge == "alpha")
        #expect(version("5-beta").badge == "beta")
        #expect(version("6-rc").badge == "rc")
        // … or the name when the id doesn't say.
        #expect(version("5", name: "5.0 (alpha)").badge == "alpha")
        // Pre-release with no hint falls back to "beta".
        #expect(version("next").badge == "beta")
        // Explicit label wins.
        #expect(version("5-beta", label: "preview").badge == "preview")
        // Stable versions carry no badge.
        #expect(version("4", prerelease: false).badge == nil)
    }

    @Test("Non-default version carries an id URL segment")
    func nonDefaultUrlSegment() {
        let version = PackageVersion("5-alpha", ref: "main", isPrerelease: true, modules: [Module("X")])
        #expect(version.urlSegment == "5-alpha/")
        #expect(version.name == "5-alpha") // name falls back to id
    }

    @Test("Group falls back from module to package to nil")
    func groupInheritance() {
        let vapor = Module("Vapor")                     // inherits package group
        let xctVapor = Module("XCTVapor", group: "Testing") // own group wins
        let ungrouped = Module("Ungrouped")             // inherits package group too
        let package = APIPackage(
            "vapor/vapor",
            group: "Core",
            versions: [PackageVersion("1", ref: "main", isDefault: true, modules: [vapor, xctVapor, ungrouped])]
        )
        #expect(package.group(for: vapor) == "Core")
        #expect(package.group(for: xctVapor) == "Testing")
        #expect(package.group(for: ungrouped) == "Core")

        let z = Module("Z")
        let noGroup = APIPackage("x/y", versions: [.single(ref: "main", modules: [z])])
        #expect(noGroup.group(for: z) == nil)
    }

    @Test("Module display title defaults to the target name")
    func displayTitle() {
        #expect(Module("Vapor").displayTitle == "Vapor")
        #expect(Module("VaporTesting", title: "Vapor Testing").displayTitle == "Vapor Testing")
    }

    @Test("An empty package list is rejected")
    func noPackages() {
        let docc = DocCSite(packages: [])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("A package with no modules is rejected")
    func packageWithNoModules() {
        let docc = DocCSite(packages: [
            APIPackage("x/y", versions: [PackageVersion("1", ref: "main", isDefault: true, modules: [])]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("Duplicate module names across packages are rejected")
    func duplicateModuleNames() {
        let docc = DocCSite(packages: [
            APIPackage("a/one", versions: [.single(ref: "main", modules: [Module("Shared")])]),
            APIPackage("b/two", versions: [.single(ref: "main", modules: [Module("Shared")])]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("Duplicate package repos are rejected")
    func duplicateRepos() {
        let docc = DocCSite(packages: [
            APIPackage("vapor/vapor", versions: [.single(ref: "main", modules: [Module("A")])]),
            APIPackage("vapor/vapor", versions: [.single(ref: "vapor-4", modules: [Module("B")])]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("A package with no default version is rejected")
    func noDefaultVersion() {
        let docc = DocCSite(packages: [
            APIPackage("x/y", versions: [
                PackageVersion("1", ref: "main", modules: [Module("Z")]),
            ]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("Multiple default versions are rejected")
    func multipleDefaultVersions() {
        let docc = DocCSite(packages: [
            APIPackage("x/y", versions: [
                PackageVersion("1", ref: "main", isDefault: true, modules: [Module("Z")]),
                PackageVersion("2", ref: "dev", isDefault: true, modules: [Module("Z")]),
            ]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("A pre-release default version is rejected")
    func prereleaseDefault() {
        let docc = DocCSite(packages: [
            APIPackage("x/y", versions: [
                PackageVersion("1", ref: "main", isDefault: true, isPrerelease: true, modules: [Module("Z")]),
            ]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("Invalid version ids (slash/whitespace/empty) are rejected")
    func invalidVersionIDs() {
        for bad in ["a/b", "a b", ""] {
            let docc = DocCSite(packages: [
                APIPackage("x/y", versions: [
                    PackageVersion(bad, ref: "main", isDefault: true, modules: [Module("Z")]),
                ]),
            ])
            #expect(throws: DocCConfigurationError.self) { try docc.validate() }
        }
    }

    @Test("Version ids unique within a package but may repeat across packages")
    func versionIDScope() throws {
        // Duplicate within a package → rejected.
        let dup = DocCSite(packages: [
            APIPackage("x/y", versions: [
                PackageVersion("2", ref: "main", isDefault: true, modules: [Module("Z")]),
                PackageVersion("2", ref: "dev", modules: [Module("Z")]),
            ]),
        ])
        #expect(throws: DocCConfigurationError.self) { try dup.validate() }

        // Same id "2" in two different packages → allowed.
        let shared = DocCSite(packages: [
            APIPackage("a/one", versions: [PackageVersion("2", ref: "main", isDefault: true, modules: [Module("A")])]),
            APIPackage("b/two", versions: [PackageVersion("2", ref: "main", isDefault: true, modules: [Module("B")])]),
        ])
        try shared.validate()
    }
}
