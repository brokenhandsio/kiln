# Kiln

**Kiln** is a documentation website generator written in Swift. You describe
your site in a type-safe Swift configuration and Kiln turns a directory of
markdown into a fast, modern static website — no YAML, no Python toolchain.

It was built as a replacement for MkDocs-based documentation sites (such as
[Vapor's](https://docs.vapor.codes)), so it covers the features those sites rely
on: multi-language docs with fallback, a themeable UI, client-side search,
admonitions, and more.

> [!NOTE]
> Kiln is under active development ahead of a 1.0 release. APIs may change.

## Features

- **Swift-defined configuration** — your whole site is a `KilnSite` value.
- **Localisation** — multiple languages with automatic fallback to your default
  language, per-language navigation translations, and a language switcher.
- **A fresh default theme** — modern, responsive, light/dark colour schemes,
  fully overridable with your own [Leaf](https://github.com/vapor/leaf-kit)
  templates.
- **Markdown** powered by [swift-markdown](https://github.com/apple/swift-markdown):
  GFM tables, fenced code with syntax highlighting, plus MkDocs-style
  admonitions (`!!! tip`, `??? note`) and heading anchors / table of contents.
- **Search** — a client-side search index is generated per language.
- **Custom error pages** and front-matter (`meta`) support.

Planned: versioned documentation, a `kiln` CLI, and an automated `mkdocs.yml`
importer.

## Installation

Add Kiln to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/brokenhandsio/kiln.git", from: "1.0.0"),
],
targets: [
    .executableTarget(
        name: "Docs",
        dependencies: [.product(name: "Kiln", package: "kiln")]
    ),
]
```

Requires Swift 6.0+ on macOS 13+ or Linux.

## Usage

```swift
import Kiln

let site = KilnSite(
    name: "My Docs",
    url: "https://docs.example.com",
    repository: .init(name: "GitHub", url: "https://github.com/me/project"),
    theme: .default(palette: .autoLightDark(primary: .black, accent: .blue)),
    languages: [
        .init(locale: "en", name: "English", isDefault: true),
        .init(locale: "de", name: "Deutsch", navTranslations: ["Guides": "Anleitungen"]),
    ],
    navigation: {
        Page("Welcome", "index.md")
        Section("Guides") {
            Page("Configuration", "guides/configuration.md")
        }
        Link("API Reference", "https://example.com/api")
    }
)

try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "public")
```

Content lives as markdown under the content directory. Translations use a locale
suffix on the filename: `index.md` is the default language, `index.de.md` its
German translation. Both share the logical path `index.md`, which is what
navigation references.

A complete, runnable example lives in
[`Examples/ExampleSite`](Examples/ExampleSite) — run it with:

```sh
cd Examples/ExampleSite
swift run
python3 -m http.server --directory public
```

## Custom themes

Kiln ships a default theme as a package resource. To customise it, point Kiln at
a directory of your own Leaf templates and assets:

```swift
theme: .custom(directory: "Theme")
```

Templates resolve from your directory first and fall back to the bundled theme,
so you only override what you need (`templates/base.leaf`, `templates/page.leaf`,
`partials/nav-tree.leaf`, `css/theme.css`, …).

## License

MIT. See [LICENSE](LICENSE).
