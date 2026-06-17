import Kiln

// Kiln's own documentation site — and, by being a real consumer of the package,
// the canonical example of how to configure Kiln. A downstream project (such as
// Vapor's docs) is set up exactly the same way: define a `KilnSite` in Swift and
// call `Kiln.build`.
//
// This site is also *versioned*: the current docs are the default ("Latest")
// version at the root, and a minimal "0.9" version under `/0.9/` demonstrates the
// version switcher. Each version has its own content directory, navigation, and
// languages.

// The full, current documentation (English + German). This is the default
// version, served at the site root with unchanged URLs.
let latest = DocVersion(
    id: "latest",
    name: "latest (v1)",
    isDefault: true,
    contentDirectory: "latest",
    languages: [
        .init(
            .english,
            isDefault: true,
            // Theme-defined strings, looked up in templates with `#t("key")`
            // (see Theme/templates/partials/footer.leaf). English is the default
            // language, so these also act as the fallback for any locale that
            // doesn't translate a given key.
            customStrings: ["tagline": "Type-safe documentation sites, built in Swift."]
        ),
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
            customStrings: ["tagline": "Typsichere Dokumentations-Websites, gebaut in Swift."],
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
                toggleColourScheme: "Farbschema umschalten",
                oldVersionMessage: "Sie sehen die Dokumentation für eine ältere Version.",
                oldVersionLink: "Zur neuesten Version",
                preReleaseMessage: "Sie sehen die Dokumentation für eine Vorabversion.",
                preReleaseLink: "Zur neuesten stabilen Version"
            )
        ),
    ]
) {
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

// A pre-release version, marked as such so the switcher and banner treat it
// differently from an older release.
let v2alpha = DocVersion(
    id: "2.0.0-alpha.1",
    name: "2.0.0-alpha.1",
    isPrerelease: true,
    contentDirectory: "2.0.0-alpha.1",
    languages: [.init(.english, isDefault: true)]
) {
    Page("Welcome", "index.md")
}

// A minimal older version, just one page — purely to demonstrate versioning.
let v0_9 = DocVersion(
    id: "0.9",
    name: "0.9",
    contentDirectory: "0.9",
    languages: [.init(.english, isDefault: true)]
) {
    Page("Welcome", "index.md")
}

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
        // The default (latest) version's content lives under Content/latest/.
        editURI: "https://github.com/brokenhandsio/kiln/edit/main/Examples/ExampleSite/Content/latest/"
    ),
    copyright: "© 2026 Broken Hands. Licensed under MIT.",
    // A custom theme that overrides a single partial (the footer, to show off a
    // localised `#t("tagline")`) and inherits everything else — templates *and*
    // CSS/JS — from the bundled default theme. See guides/theming.
    theme: .custom(
        directory: "Theme",
        palette: .autoLightDark(primary: .black, accent: .blue),
        logo: "assets/logo.svg",
        favicon: "assets/logo.svg"
    ),
    social: [
        .init(icon: .github, link: "https://github.com/brokenhandsio/kiln"),
        .init(icon: .mastodon, link: "https://hachyderm.io/@brokenhandsio"),
    ],
    // Newest first: the pre-release, then the latest stable, then older versions.
    versions: [v2alpha, latest, v0_9]
)

let contentDirectory = "Content"
let outputDirectory = "public"

print("Building site into ./\(outputDirectory) …")
// `.error` fails the build on any broken internal link, so CI catches them.
try await Kiln.build(site, contentDirectory: contentDirectory, outputDirectory: outputDirectory, linkChecking: .error)
print("Done. Serve it with:  kiln serve --directory \(outputDirectory)")
