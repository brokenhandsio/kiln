import Testing
@testable import Kiln

@Suite("DocC configuration")
struct DocCConfigurationTests {
    /// A representative multi-package config used across the happy-path tests.
    private func sampleSite() -> DocCSite {
        DocCSite(
            packages: [
                APIPackage(
                    "vapor/vapor",
                    modules: [
                        Module("Vapor", group: "Core", description: "Core web framework"),
                        Module("XCTVapor", group: "Testing"),
                    ],
                    versions: [
                        PackageVersion("4", name: "4.x", ref: "vapor-4", isDefault: true),
                        PackageVersion("5-alpha", name: "5.0 (alpha)", ref: "main", isPrerelease: true),
                    ]
                ),
                APIPackage("vapor/leaf-kit", ref: "main", group: "Templating", modules: [
                    Module("LeafKit"),
                ]),
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

    @Test("Single-version shorthand synthesises one default version")
    func shorthandDefaultVersion() {
        let package = APIPackage("vapor/leaf-kit", ref: "main", modules: [Module("LeafKit")])
        #expect(package.versions.count == 1)
        #expect(package.defaultVersion.isDefault)
        #expect(package.defaultVersion.ref == "main")
        #expect(package.defaultVersion.urlSegment == "")
    }

    @Test("Non-default version carries an id URL segment")
    func nonDefaultUrlSegment() {
        let version = PackageVersion("5-alpha", ref: "main", isPrerelease: true)
        #expect(version.urlSegment == "5-alpha/")
        #expect(version.name == "5-alpha") // name falls back to id
    }

    @Test("Group falls back from module to package to nil")
    func groupInheritance() {
        let package = APIPackage(
            "vapor/vapor",
            group: "Core",
            modules: [
                Module("Vapor"),                    // inherits package group
                Module("XCTVapor", group: "Testing"), // own group wins
                Module("Ungrouped"),                 // inherits package group too
            ],
            versions: [PackageVersion("1", ref: "main", isDefault: true)]
        )
        #expect(package.group(for: package.modules[0]) == "Core")
        #expect(package.group(for: package.modules[1]) == "Testing")
        #expect(package.group(for: package.modules[2]) == "Core")

        let noGroup = APIPackage("x/y", ref: "main", modules: [Module("Z")])
        #expect(noGroup.group(for: noGroup.modules[0]) == nil)
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
            APIPackage("x/y", modules: [], versions: [PackageVersion("1", ref: "main", isDefault: true)]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("Duplicate module names across packages are rejected")
    func duplicateModuleNames() {
        let docc = DocCSite(packages: [
            APIPackage("a/one", ref: "main", modules: [Module("Shared")]),
            APIPackage("b/two", ref: "main", modules: [Module("Shared")]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("Duplicate package repos are rejected")
    func duplicateRepos() {
        let docc = DocCSite(packages: [
            APIPackage("vapor/vapor", ref: "main", modules: [Module("A")]),
            APIPackage("vapor/vapor", ref: "vapor-4", modules: [Module("B")]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("A package with no default version is rejected")
    func noDefaultVersion() {
        let docc = DocCSite(packages: [
            APIPackage("x/y", modules: [Module("Z")], versions: [
                PackageVersion("1", ref: "main"),
            ]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("Multiple default versions are rejected")
    func multipleDefaultVersions() {
        let docc = DocCSite(packages: [
            APIPackage("x/y", modules: [Module("Z")], versions: [
                PackageVersion("1", ref: "main", isDefault: true),
                PackageVersion("2", ref: "dev", isDefault: true),
            ]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("A pre-release default version is rejected")
    func prereleaseDefault() {
        let docc = DocCSite(packages: [
            APIPackage("x/y", modules: [Module("Z")], versions: [
                PackageVersion("1", ref: "main", isDefault: true, isPrerelease: true),
            ]),
        ])
        #expect(throws: DocCConfigurationError.self) { try docc.validate() }
    }

    @Test("Invalid version ids (slash/whitespace/empty) are rejected")
    func invalidVersionIDs() {
        for bad in ["a/b", "a b", ""] {
            let docc = DocCSite(packages: [
                APIPackage("x/y", modules: [Module("Z")], versions: [
                    PackageVersion(bad, ref: "main", isDefault: true),
                ]),
            ])
            #expect(throws: DocCConfigurationError.self) { try docc.validate() }
        }
    }

    @Test("Version ids unique within a package but may repeat across packages")
    func versionIDScope() throws {
        // Duplicate within a package → rejected.
        let dup = DocCSite(packages: [
            APIPackage("x/y", modules: [Module("Z")], versions: [
                PackageVersion("2", ref: "main", isDefault: true),
                PackageVersion("2", ref: "dev"),
            ]),
        ])
        #expect(throws: DocCConfigurationError.self) { try dup.validate() }

        // Same id "2" in two different packages → allowed.
        let shared = DocCSite(packages: [
            APIPackage("a/one", modules: [Module("A")], versions: [PackageVersion("2", ref: "main", isDefault: true)]),
            APIPackage("b/two", modules: [Module("B")], versions: [PackageVersion("2", ref: "main", isDefault: true)]),
        ])
        try shared.validate()
    }
}
