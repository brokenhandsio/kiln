import Kiln

/// A selectable language for `kiln new`, pairing a ``LanguageCode`` with the
/// Swift source literal used when generating `main.swift`.
struct LanguageOption: Sendable {
    let code: LanguageCode
    /// The Swift expression to emit, e.g. `".english"`.
    let literal: String

    var displayName: String { code.name }
    var localeCode: String { code.code }
}

/// The built-in languages offered by the `new` command's picker, in the same
/// order as `LanguageCode`'s cases.
let builtInLanguageOptions: [LanguageOption] = [
    .init(code: .english, literal: ".english"),
    .init(code: .german, literal: ".german"),
    .init(code: .spanish, literal: ".spanish"),
    .init(code: .french, literal: ".french"),
    .init(code: .italian, literal: ".italian"),
    .init(code: .japanese, literal: ".japanese"),
    .init(code: .korean, literal: ".korean"),
    .init(code: .dutch, literal: ".dutch"),
    .init(code: .polish, literal: ".polish"),
    .init(code: .chinese, literal: ".chinese"),
    .init(code: .traditionalChinese, literal: ".traditionalChinese"),
    .init(code: .portuguese, literal: ".portuguese"),
    .init(code: .brazilianPortuguese, literal: ".brazilianPortuguese"),
    .init(code: .russian, literal: ".russian"),
    .init(code: .ukrainian, literal: ".ukrainian"),
    .init(code: .turkish, literal: ".turkish"),
    .init(code: .arabic, literal: ".arabic"),
    .init(code: .hindi, literal: ".hindi"),
    .init(code: .indonesian, literal: ".indonesian"),
    .init(code: .vietnamese, literal: ".vietnamese"),
    .init(code: .thai, literal: ".thai"),
    .init(code: .czech, literal: ".czech"),
    .init(code: .swedish, literal: ".swedish"),
    .init(code: .norwegian, literal: ".norwegian"),
    .init(code: .danish, literal: ".danish"),
    .init(code: .finnish, literal: ".finnish"),
    .init(code: .greek, literal: ".greek"),
    .init(code: .hebrew, literal: ".hebrew"),
    .init(code: .hungarian, literal: ".hungarian"),
    .init(code: .romanian, literal: ".romanian"),
]

/// Inputs gathered (interactively or otherwise) for a new project.
struct ScaffoldInput: Sendable {
    var targetName: String
    var siteName: String
    var url: String
    var defaultLanguage: LanguageOption
    var otherLanguages: [LanguageOption]
}

/// Pure generators for the files written by `kiln new`. Kept side-effect-free
/// so they can be unit-tested.
enum Scaffold {
    static func packageSwift(input: ScaffoldInput) -> String {
        """
        // swift-tools-version:6.0
        import PackageDescription

        let package = Package(
            name: "\(input.targetName)",
            platforms: [
                .macOS(.v13)
            ],
            dependencies: [
                .package(url: "https://github.com/brokenhandsio/kiln.git", from: "\(kilnVersion)"),
            ],
            targets: [
                .executableTarget(
                    name: "\(input.targetName)",
                    dependencies: [
                        .product(name: "Kiln", package: "kiln"),
                    ]
                ),
            ]
        )
        """
    }

    static func mainSwift(input: ScaffoldInput) -> String {
        var languageLines = ["        Language(\(input.defaultLanguage.literal), isDefault: true),"]
        for language in input.otherLanguages {
            languageLines.append("        Language(\(language.literal)),")
        }
        let languages = languageLines.joined(separator: "\n")

        return """
        import Kiln

        let site = KilnSite(
            name: "\(input.siteName)",
            url: "\(input.url)",
            description: "Documentation for \(input.siteName).",
            languages: [
        \(languages)
            ],
            navigation: {
                Page("Welcome", "index.md")
            }
        )

        try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "site")
        """
    }

    static func indexMarkdown(input: ScaffoldInput) -> String {
        """
        # Welcome to \(input.siteName)

        This is your new documentation site, generated with [Kiln](https://github.com/brokenhandsio/kiln).

        Edit `Content/index.md` to change this page, and add more markdown files
        under `Content/`. Wire them into the navigation in `Sources/\(input.targetName)/main.swift`.

        !!! tip
            Run `kiln serve` to preview your site at http://127.0.0.1:8080 with
            automatic rebuilds when you edit a file.
        """
    }

    static func localisedIndexMarkdown(input: ScaffoldInput, language: LanguageOption) -> String {
        """
        # \(input.siteName)

        This is the \(language.displayName) translation of your home page. Replace
        this text with your translated content.
        """
    }

    static func gitignore() -> String {
        """
        .build/
        .swiftpm/
        site/
        """
    }

    static func readme(input: ScaffoldInput) -> String {
        """
        # \(input.siteName)

        Documentation site built with [Kiln](https://github.com/brokenhandsio/kiln).

        ## Develop

        ```sh
        kiln serve     # build + preview at http://127.0.0.1:8080, rebuilding on change
        ```

        ## Build

        ```sh
        kiln build     # writes the static site to ./site
        ```
        """
    }
}
