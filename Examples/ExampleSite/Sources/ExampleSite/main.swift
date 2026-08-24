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

// Theme-defined strings looked up in templates with `#localise("key")` (see
// Theme/templates/partials/footer.leaf). Shared by every version's English
// language so the footer reads the same everywhere.
let footerStrings = [
    "tagline": "Type-safe documentation sites, built in Swift.",
    "legal": "Legal",
]

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
            // English is the default language, so these also act as the fallback
            // for any locale that doesn't translate a given key.
            customStrings: footerStrings
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
                "Static Sites": "Statische Websites",
                "Blog": "Blog",
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
            customStrings: [
                "tagline": "Typsichere Dokumentations-Websites, gebaut in Swift.",
                "legal": "Rechtliches",
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
                toggleColourScheme: "Farbschema umschalten",
                oldVersionMessage: "Sie sehen die Dokumentation für eine ältere Version.",
                oldVersionLink: "Zur neuesten Version",
                preReleaseMessage: "Sie sehen die Dokumentation für eine Vorabversion.",
                preReleaseLink: "Zur neuesten stabilen Version"
            )
        ),
    ],
    // Built and translated like any other page, but absent from the navigation —
    // the footer links to it (see Theme/templates/partials/footer.leaf).
    unlistedPages: [UnlistedPage("Legal", "legal.md")]
) {
    Page("Welcome", "index.md")
    Section("Getting Started") {
        Page("Installation", "getting-started/installation.md")
        Page("Quick Start", "getting-started/quick-start.md")
        Page("The CLI", "getting-started/cli.md")
    }
    Section("Guides") {
        Page("Configuration", "guides/configuration.md")
        Page("Static Sites", "guides/static-sites.md")
        Page("Blog", "guides/blog.md")
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
    // The shared footer is rendered for every version, so each one needs the
    // theme's custom strings — an unresolved key renders as the key itself.
    languages: [.init(.english, isDefault: true, customStrings: footerStrings)]
) {
    Page("Welcome", "index.md")
}

// A minimal older version, just one page — purely to demonstrate versioning.
let v0_9 = DocVersion(
    id: "0.9",
    name: "0.9",
    contentDirectory: "0.9",
    languages: [.init(.english, isDefault: true, customStrings: footerStrings)]
) {
    Page("Welcome", "index.md")
}

let site = KilnSite(
    name: "Kiln",
    // TODO: point this at the real deployment domain before going live.
    url: "https://kiln.brokenhands.io",
    author: "Broken Hands",
    description: "Kiln is a documentation-site generator written in Swift — type-safe config, localisation, theming, and client-side search.",
    // Default social/OpenGraph preview image — a 1200×630 PNG, since social
    // scrapers (Slack, X, iMessage, …) handle raster far more reliably than SVG.
    image: "assets/social-card.png",
    twitterSite: "@brokenhandsio",
    // JSON-LD publisher entity — emits Organization + WebSite structured data so
    // search engines can build a richer knowledge-graph node. `logo` must be an
    // absolute URL to a raster image (≥112×112).
    organization: .init(
        name: "Kiln",
        url: "https://kiln.brokenhands.io",
        logo: "https://kiln.brokenhands.io/assets/logo.png",
        sameAs: [
            "https://github.com/brokenhandsio/kiln",
            "https://hachyderm.io/@brokenhandsio",
        ]
    ),
    repository: .init(
        name: "GitHub",
        url: "https://github.com/brokenhandsio/kiln",
        // The default (latest) version's content lives under Content/latest/.
        editURI: "https://github.com/brokenhandsio/kiln/edit/main/Examples/ExampleSite/Content/latest/"
    ),
    copyright: "© 2026 Broken Hands. Licensed under MIT.",
    // A custom theme that overrides a single partial (the footer, to show off a
    // localised `#localise("tagline")`) and inherits everything else — templates *and*
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
