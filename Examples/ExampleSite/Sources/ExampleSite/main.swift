import Kiln

// A small but representative documentation site. This is exactly how a
// downstream project (such as Vapor's docs) would configure Kiln: define a
// `KilnSite` in Swift and call `Kiln.build`.
let site = KilnSite(
    name: "Kiln Example",
    url: "https://example.com",
    author: "Broken Hands",
    description: "An example documentation site built with Kiln.",
    // Default social/OpenGraph preview image. Real sites should use a PNG/JPG
    // for best social-scraper support; an SVG is used here just to demo wiring.
    image: "assets/social-card.svg",
    twitterSite: "@brokenhandsio",
    repository: .init(
        name: "GitHub",
        url: "https://github.com/brokenhandsio/kiln",
        editURI: "https://github.com/brokenhandsio/kiln/edit/main/Examples/ExampleSite/Content/"
    ),
    copyright: "© 2026 Broken Hands. Licensed under MIT.",
    theme: .default(
        palette: .autoLightDark(primary: .black, accent: .blue),
        logo: "assets/logo.svg",
        favicon: "assets/logo.svg"
    ),
    social: [
        .init(icon: .github, link: "https://github.com/brokenhandsio"),
        .init(icon: .mastodon, link: "https://hachyderm.io/@kiln"),
    ],
    languages: [
        .init(locale: "en", name: "English", isDefault: true),
        .init(
            locale: "de",
            name: "Deutsch",
            siteName: "Kiln Beispiel",
            navTranslations: [
                "Welcome": "Willkommen",
                "Getting Started": "Erste Schritte",
                "Installation": "Installation",
                "Quick Start": "Schnellstart",
                "Guides": "Anleitungen",
                "Configuration": "Konfiguration",
                "Theming": "Themengestaltung",
            ]
        ),
    ],
    navigation: {
        Page("Welcome", "index.md")
        Section("Getting Started") {
            Page("Installation", "getting-started/installation.md")
            Page("Quick Start", "getting-started/quick-start.md")
        }
        Section("Guides") {
            Page("Configuration", "guides/configuration.md")
            Page("Theming", "guides/theming.md")
        }
        Link("API Reference", "https://swiftpackageindex.com")
    }
)

let contentDirectory = "Content"
let outputDirectory = "public"

print("Building site into ./\(outputDirectory) …")
try await Kiln.build(site, contentDirectory: contentDirectory, outputDirectory: outputDirectory)
print("Done. Serve it with:  python3 -m http.server --directory \(outputDirectory)")
