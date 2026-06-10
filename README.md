# Kiln

**Kiln** is a documentation tool for projects that provides first class support for multiple versions and localisation. It works as a static site generator written in Swift. You describe
your site in a type-safe Swift configuration and Kiln turns a directory of
markdown into a fast, modern static website — no YAML, no Python toolchain.

It was built as a replacement for MkDocs-based documentation sites (such as
[Vapor's](https://docs.vapor.codes)), so it covers the features those sites rely
on: multi-language docs with fallback, a themeable UI, client-side search,
admonitions, and more.

📖 **See it in action:** Kiln's own documentation site — built with Kiln — is
live at **[kiln.brokenhands.io](https://kiln.brokenhands.io)**. Its source is the
[example site](Examples/ExampleSite) in this repo.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [The `kiln` CLI](#the-kiln-cli)
- [Content & localisation](#content--localisation)
- [Navigation](#navigation)
- [Markdown](#markdown)
- [Configuration reference](#configuration-reference)
- [Theming](#theming)
- [Search](#search)
- [Output](#output)
- [Example site](#example-site)
- [Development](#development)
- [License](#license)

## Features

- **Swift-defined configuration** — your whole site is a single type-safe
  `KilnSite` value with a navigation result-builder DSL.
- **Versioned docs** — define multiple documentation versions with a built-in
  version switcher. The default ("latest") version is served at the site root and
  others under `/<version>/`, with automatic banners for pre-release and outdated
  versions.
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
- **Custom error pages** (a styled 404), pretty URLs, automatic asset copying,
  and optional [Carbon Ads](https://www.carbonads.net).
- **Build-time link checking** — internal `.md` links (incl. localised
  `content.de.md` targets), `#anchor` fragments, and relative assets are
  validated against the built site; warn or fail the build.
- **AI / agent-friendly** — generates an [`llms.txt`](https://llmstxt.org) index
  and `llms-full.txt` corpus, plus a raw-markdown copy of every page
  (`…/index.md`) with a `<link rel="alternate" type="text/markdown">` for
  discovery.
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
        .init(.english, isDefault: true),
        .init(.german, navTranslations: ["Guides": "Anleitungen"]),
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

…or use the [`kiln` CLI](#the-kiln-cli), which builds and previews for you:

```sh
kiln serve
```

## The `kiln` CLI

Kiln ships a command-line tool that wraps the common workflows. Because a Kiln
site is defined in Swift, `kiln` drives your project's own executable (via
`swift run`) rather than reading a config file — so the conventions are: your
build writes to `./site`, and your content lives in `./Content`.

### Install

With [Homebrew](https://brew.sh) (macOS, Apple Silicon):

```sh
brew install brokenhandsio/tap/kiln
```

Or build the `kiln` product from source (any platform with a Swift toolchain,
including Intel Macs and Linux):

```sh
git clone https://github.com/brokenhandsio/kiln.git
cd kiln
swift build -c release
cp .build/release/kiln /usr/local/bin/   # or anywhere on your PATH
```

### `kiln new [path]`

Interactively scaffold a new documentation project — prompts for the site name,
URL, default language, and any additional languages (from Kiln's built-in
locale list), then writes a ready-to-build SwiftPM package:

```sh
kiln new my-docs
cd my-docs
kiln serve
```

### `kiln serve`

Build the site and serve it locally, rebuilding automatically when you edit a
file:

```sh
kiln serve                       # build, serve ./site at http://127.0.0.1:8080, watch for changes
kiln serve --port 3000           # change the port
kiln serve --directory public    # serve a different output directory
kiln serve --no-watch            # build + serve once, no rebuild-on-change
kiln serve --no-build            # serve the existing output without building first
```

The watcher polls for changes (skipping `.build`, `.git`, `.swiftpm`, and the
output directory) and re-runs the build; reload your browser to see updates.

### `kiln build`

Build the site by running your project's executable:

```sh
kiln build                       # writes the static site (to ./site by convention)
kiln build --release             # build in release configuration
```

> [!NOTE]
> `kiln` is optional — everything it does, you can also do with `swift run` plus
> any static file server. It's there for convenience and a familiar
> `mkdocs`-style workflow.

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

### Interface strings

The theme's own UI strings (search box, navigation labels, error page, …) are
localised per language via `LocalisationConfiguration`. Any string left unset
falls back to Kiln's built-in English default:

```swift
Language(.german, localisation: .init(
    searchPlaceholder: "Suchen",
    searchNoResults: "Keine Ergebnisse gefunden",
    tableOfContentsTitle: "Auf dieser Seite",
    previousPage: "Zurück",
    nextPage: "Weiter",
    editPage: "Diese Seite bearbeiten",
    notFoundTitle: "Seite nicht gefunden"
    // … and more; see LocalisationConfiguration
))
```

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
| `carbonAds`       | `CarbonAds?`          | [Carbon Ads](https://www.carbonads.net) `serve`/`placement`; shown in the TOC sidebar on desktop. |
| `extraCSS`        | `[String]`            | Extra stylesheets (relative to the content dir). |
| `extraJavaScript` | `[String]`            | Extra scripts. |
| `languages`       | `[Language]`          | Each `Language(_ code: LanguageCode, …)` — a built-in case like `.english`/`.german` or `.custom(code:name:)` — with `isDefault`, `build`, `siteName`, `description`, `navTranslations`, `localisation`. |
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
build-time JavaScript toolchain required. Tokenisation is Unicode-aware: accented
Latin scripts are matched whole, and Han/kana (which aren't space-separated) are
segmented into bigrams so CJK queries work.

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
├── index.md                       # raw-markdown copy of each page (for AI tools)
├── guides/configuration/index.md
├── _kiln/                         # bundled theme assets (css/js)
├── sitemap.xml
├── robots.txt
├── llms.txt                       # AI/agent index (llmstxt.org)
├── llms-full.txt                  # full markdown corpus
└── …                              # your content assets, copied as-is
```

## Example site

[`Examples/ExampleSite`](Examples/ExampleSite) is **Kiln's own documentation
site** — a complete, runnable project that consumes Kiln as a dependency, and
the canonical reference for how a real site is wired together (multi-page nav,
localisation with fallback, SEO, search, and a `0.9` version that demonstrates
the version switcher). Build and preview it with the CLI:

```sh
cd Examples/ExampleSite
kiln serve --directory public
```

(or `swift run && python3 -m http.server --directory public` without the CLI).

## Development

```sh
swift build
swift test
```

CI builds and tests on both macOS and Linux and verifies the example site builds
on every push to `main` and every pull request.

## License

MIT. See [LICENSE](LICENSE).
