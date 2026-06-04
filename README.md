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

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Content & localisation](#content--localisation)
- [Navigation](#navigation)
- [Markdown](#markdown)
- [Configuration reference](#configuration-reference)
- [Theming](#theming)
- [Search](#search)
- [Output](#output)
- [Example site](#example-site)
- [Roadmap](#roadmap)
- [Development](#development)
- [License](#license)

## Features

- **Swift-defined configuration** — your whole site is a single type-safe
  `KilnSite` value with a navigation result-builder DSL.
- **Localisation** — multiple languages with automatic fallback to your default
  language, per-language navigation translations and site names, hreflang
  alternates, and a language switcher.
- **A fresh default theme** — modern, responsive, with light/dark colour
  schemes, a sidebar nav, an on-page table of contents, and search. Fully
  overridable with your own [Leaf](https://github.com/vapor/leaf-kit) templates.
- **Markdown** powered by [swift-markdown](https://github.com/apple/swift-markdown):
  GFM tables, fenced code with syntax highlighting, MkDocs-style admonitions
  (`!!! tip`, `??? note`), heading anchors + table of contents, and optional
  YAML front matter.
- **Search** — a client-side search index is generated per language (no external
  service, no build-time JS toolchain).
- **SEO & social cards** — per-page `<title>`/description, canonical URLs,
  hreflang alternates, OpenGraph and Twitter card tags (with a site-wide default
  preview image and per-page front-matter overrides), plus `sitemap.xml` and
  `robots.txt`.
- **Custom error pages**, pretty URLs, and automatic asset copying.
- **Cross-platform** — builds and runs on macOS and Linux.

## Requirements

- Swift **6.2+** (the package enables upcoming/experimental Swift features that
  target 6.2).
- macOS 13+ or Linux.

## Installation

Add Kiln to your `Package.swift` and create a small executable that builds your
site:

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

## Quick start

```swift
import Kiln

let site = KilnSite(
    name: "My Docs",
    url: "https://docs.example.com",
    description: "Documentation for My Project.",
    repository: .init(
        name: "GitHub",
        url: "https://github.com/me/project",
        editURI: "https://github.com/me/project/edit/main/Content/"
    ),
    theme: .default(palette: .autoLightDark(primary: .black, accent: .blue)),
    social: [.init(icon: .github, link: "https://github.com/me/project")],
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

Run it, then serve the output with any static file server:

```sh
swift run Docs
python3 -m http.server --directory public
```

## Content & localisation

Content is plain markdown under your content directory. Translations use a
**locale suffix** on the filename:

```
Content/
├── index.md          # default language (e.g. English)
├── index.de.md       # German translation of the home page
└── guides/
    ├── configuration.md
    └── configuration.de.md
```

`index.md` and `index.de.md` share the same **logical path** (`index.md`), which
is what navigation references. When a page has no translation for a language,
Kiln falls back to the default language's content and shows a small "translation
unavailable" banner — the equivalent of mkdocs-static-i18n's
`fallback_to_default: true`.

The default language is built at the site root; other languages live under
`/<locale>/`.

## Navigation

The navigation tree is built with a result builder using three helpers:

```swift
navigation: {
    Page("Welcome", "index.md")        // a markdown page (path is the logical path)
    Section("Guides") {                 // a collapsible group
        Page("Configuration", "guides/configuration.md")
        Page("Theming", "guides/theming.md")
    }
    Link("API Reference", "https://example.com/api")  // an external link
}
```

Section and page titles are translated per language via each `Language`'s
`navTranslations` map (keyed on the default-language title). Kiln also derives
previous/next links and the active trail automatically.

## Markdown

Supported out of the box:

- **Headings** with GitHub-style slug `id`s, permalink anchors, and an
  automatically generated table of contents.
- **GFM tables**, **fenced code blocks** (highlighted client-side with
  highlight.js), inline formatting, links, images, blockquotes, ordered/
  unordered/task lists.
- **Admonitions** — MkDocs/Python-Markdown style:

  ```markdown
  !!! tip "Optional title"
      Body content, rendered as markdown.

  ??? note "Collapsible"
      Hidden until expanded (use `???+` to start expanded).
  ```

- **Front matter** (the `meta` extension) — an optional YAML block at the top of
  a file:

  ```markdown
  ---
  title: Custom Page Title
  description: Used for meta and social tags.
  image: assets/custom-card.png   # per-page social preview image
  template: landing               # override the Leaf template for this page
  ---
  ```

## Configuration reference

`KilnSite` is the single source of truth:

| Field             | Type                  | Notes |
| ----------------- | --------------------- | ----- |
| `name`            | `String`              | Site title. |
| `url`             | `String`              | Canonical site URL. |
| `author`          | `String?`             | Used for meta tags. |
| `description`     | `String?`             | Default meta/OpenGraph description. |
| `image`           | `String?`             | Default social/OpenGraph preview image (content-relative path). |
| `twitterSite`     | `String?`             | Twitter/X handle for the `twitter:site` tag (e.g. `"@codevapor"`). |
| `repository`      | `Repository?`         | `name`, `url`, optional `editURI` for "edit this page" links. |
| `copyright`       | `String?`             | Footer notice. |
| `theme`           | `Theme`               | `.default(…)` or `.custom(directory:…)`. |
| `social`          | `[SocialLink]`        | `icon` (`.github`, `.mastodon`, `.twitter`, `.discord`, `.linkedin`, `.youtube`, `.rss`, `.custom`) + `link`. |
| `extraCSS`        | `[String]`            | Extra stylesheets (relative to the content dir). |
| `extraJavaScript` | `[String]`            | Extra scripts. |
| `languages`       | `[Language]`          | `locale`, `name`, `isDefault`, `build`, `siteName`, `navTranslations`. |
| `markdown`        | `MarkdownExtensions`  | Feature toggles + `TableOfContentsOptions`. |
| `navigation`      | `@NavBuilder`         | The nav tree (see above). |

**Theme** options: `palette` (`Palette` with `primary`/`accent` `Color`s and a
`.auto`/`.light`/`.dark` default mode), `logo`, `favicon`, `fonts`
(`Fonts(text:code:)`), and `features` (`.searchSuggest`, `.searchHighlight`,
`.navigationTabs`, `.backToTop`). `Color` has presets (`.black`, `.blue`,
`.indigo`, …) or accepts any CSS string via `Color("#2f6feb")`.

## Theming

Kiln ships a default theme as a package resource. To customise it, point Kiln at
a directory of your own Leaf templates and assets:

```swift
theme: .custom(directory: "Theme")
```

Templates resolve from **your directory first** and fall back to the bundled
theme, so you only override what you need. The theme is split into small
partials:

```
Theme/
├── templates/
│   ├── base.leaf            # overall page shell (<head>, header, layout, scripts)
│   ├── page.leaf            # a standard documentation page
│   ├── home.leaf            # the home page
│   ├── 404.leaf             # the error page
│   └── partials/
│       ├── header.leaf
│       ├── footer.leaf
│       ├── nav-tree.leaf
│       ├── toc.leaf
│       ├── search.leaf
│       ├── language-switcher.leaf
│       └── social-icons.leaf
├── css/
└── js/
```

Templates receive a context with `site`, `page`, `nav`, `language`, `languages`,
and `searchIndexURL`. The rendered page body is injected with
`#unsafeHTML(page.content)`.

## Search

A search index (`search/search_index.json`) is generated per language at build
time. The bundled theme includes a small, dependency-free client that fetches
the index and ranks results in the browser — no external search service and no
build-time JavaScript toolchain required.

## Output

A build produces a static site with pretty ("directory") URLs:

```
public/
├── index.html                     # default language at the root
├── guides/configuration/index.html
├── de/                            # other languages under /<locale>/
│   ├── index.html
│   └── guides/configuration/index.html
├── search/search_index.json       # per-language search index
├── de/search/search_index.json
├── 404.html                       # per-language error pages
├── de/404.html
├── _kiln/                         # bundled theme assets (css/js)
├── sitemap.xml
└── …                              # your content assets, copied as-is
```

## Example site

A complete, runnable example that consumes Kiln as a dependency lives in
[`Examples/ExampleSite`](Examples/ExampleSite):

```sh
cd Examples/ExampleSite
swift run
python3 -m http.server --directory public
```

## Roadmap

Planned, roughly in priority order:

- **Search improvements** — a dedicated results page, better ranking, and
  search suggestions/highlighting.
- **`kiln` CLI** — `build`, `serve` (with live reload), and `new` (project
  scaffolding) for people who'd rather not write the small build executable.
- **Versioned documentation** — multiple doc versions with a version switcher.
- **`mkdocs.yml` importer** — to ease migrating existing MkDocs sites.

## Development

```sh
swift build
swift test
```

CI builds and tests on both macOS and Linux and verifies the example site builds
on every push to `main` and every pull request.

## License

MIT. See [LICENSE](LICENSE).
