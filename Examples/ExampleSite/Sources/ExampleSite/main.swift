import Kiln

// Kiln's own documentation site — and, by being a real consumer of the package,
// the canonical example of how to configure Kiln. A downstream project (such as
// Vapor's docs) is set up exactly the same way: define a `KilnSite` in Swift and
// call `Kiln.build`.
let site = KilnSite(
    name: "Kiln",
    // TODO: point this at the real deployment domain before going live.
    url: "https://kiln.brokenhands.io",
    author: "Broken Hands",
    description: "Kiln is a documentation-site generator written in Swift — type-safe config, localisation, theming, and client-side search.",
    // Default social/OpenGraph preview image. Real sites should prefer a PNG/JPG
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
        .init(icon: .github, link: "https://github.com/brokenhandsio/kiln"),
        .init(icon: .mastodon, link: "https://hachyderm.io/@brokenhandsio"),
    ],
    languages: [
        .init(.english, isDefault: true),
        .init(
            .german,
            siteName: "Kiln",
            navTranslations: [
                "Welcome": "Willkommen",
                "Getting Started": "Erste Schritte",
                "Installation": "Installation",
                "Quick Start": "Schnellstart",
                "The CLI": "Die CLI",
                "Guides": "Anleitungen",
                "Configuration": "Konfiguration",
                "Content & Localisation": "Inhalt & Lokalisierung",
                "Navigation": "Navigation",
                "Markdown": "Markdown",
                "Theming": "Themengestaltung",
                "Search": "Suche",
                "SEO & Social Cards": "SEO & Social Cards",
                "Link Checking": "Linkprüfung",
                "AI-Friendly Output": "KI-freundliche Ausgabe",
                "Deployment": "Bereitstellung",
            ],
            localisation: .init(
                searchPlaceholder: "Suchen",
                searchNoResults: "Keine Ergebnisse gefunden",
                tableOfContentsTitle: "Auf dieser Seite",
                previousPage: "Zurück",
                nextPage: "Weiter",
                editPage: "Diese Seite bearbeiten",
                fallbackTitle: "Übersetzung nicht verfügbar",
                fallbackMessage: "Diese Seite wurde noch nicht übersetzt, daher wird die Standardsprache angezeigt.",
                notFoundTitle: "Seite nicht gefunden",
                notFoundMessage: "Die gesuchte Seite wurde möglicherweise verschoben, umbenannt oder existiert nicht.",
                notFoundLink: "Zurück zur Startseite",
                toggleNavigation: "Navigation umschalten",
                toggleColourScheme: "Farbschema umschalten"
            )
        ),
    ],
    navigation: {
        Page("Welcome", "index.md")
        Section("Getting Started") {
            Page("Installation", "getting-started/installation.md")
            Page("Quick Start", "getting-started/quick-start.md")
            Page("The CLI", "getting-started/cli.md")
        }
        Section("Guides") {
            Page("Configuration", "guides/configuration.md")
            Page("Content & Localisation", "guides/content-and-localisation.md")
            Page("Navigation", "guides/navigation.md")
            Page("Markdown", "guides/markdown.md")
            Page("Theming", "guides/theming.md")
            Page("Search", "guides/search.md")
            Page("SEO & Social Cards", "guides/seo.md")
            Page("Link Checking", "guides/link-checking.md")
            Page("AI-Friendly Output", "guides/llms.md")
            Page("Deployment", "guides/deployment.md")
        }
        Link("GitHub", "https://github.com/brokenhandsio/kiln")
    }
)

let contentDirectory = "Content"
let outputDirectory = "public"

print("Building site into ./\(outputDirectory) …")
try await Kiln.build(site, contentDirectory: contentDirectory, outputDirectory: outputDirectory)
print("Done. Serve it with:  kiln serve --directory \(outputDirectory)")
