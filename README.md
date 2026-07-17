# Kiln

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbrokenhandsio%2Fkiln%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/brokenhandsio/kiln)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbrokenhandsio%2Fkiln%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/brokenhandsio/kiln)

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
- [API reference (DocC)](#api-reference-docc)
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
  alternates, and a language switcher. Right-to-left languages (Arabic, Hebrew, …)
  set `dir="rtl"` on the page automatically, and the default theme is authored with
  CSS logical properties so it mirrors correctly.
- **A fresh default theme** — modern, responsive, with light/dark colour
  schemes, a sidebar nav, an on-page table of contents, and search. Fully
  overridable with your own [Leaf](https://github.com/vapor/leaf-kit) templates.
- **Markdown** powered by [swift-markdown](https://github.com/apple/swift-markdown):
  GFM tables, fenced code with syntax highlighting, MkDocs-style admonitions
  (`!!! tip`, `??? note`), heading anchors + table of contents, and optional
  YAML front matter.
- **Search** — a client-side search index is generated per language (no external
  service, no build-time JS toolchain).
- **API reference from DocC** — ingest pre-built [DocC](https://www.swift.org/documentation/docc/)
  archives for one or more Swift packages and render them into your theme as one
  cohesive site, with a module switcher, a per-package version switcher, sitewide
  search, and a generated catalog landing page (see
  [API reference (DocC)](#api-reference-docc)).
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
kiln serve --base-path /docs     # preview a site whose basePath is "/docs" (visit http://127.0.0.1:8080/docs/)
kiln serve --pre-build "make js" # override the configured asset pre-build command for this run
kiln serve --no-pre-build        # skip the asset pre-build step this run
```

The watcher polls for changes (skipping `.build`, `.git`, `.swiftpm`,
`node_modules`, and the output directory) and re-runs the build; reload your
browser to see updates. If a `kiln.json` asset pre-build is configured (see
below), each rebuild runs it before regenerating the site.

### `kiln build`

Build the site by running your project's executable:

```sh
kiln build                       # writes the static site (to ./site by convention)
kiln build --release             # build in release configuration
kiln build --pre-build "make js" # override the configured asset pre-build command
kiln build --no-pre-build        # skip the asset pre-build step
```

### Building assets first (`kiln.json`)

If your site has an asset pipeline — say webpack or Sass compiled with `npm` —
it should run *before* the site is generated so the latest CSS/JS is picked up.
Drop an optional `kiln.json` at the project root:

```json
{
  "preBuild": {
    "command": "npm run build",
    "watch": ["src/scss", "src/js"]
  }
}
```

Both `kiln build` and `kiln serve` then run `command` before the Swift build,
streaming its output live (so webpack warnings/errors are visible). During `kiln
serve`, the directories in `watch` are watched alongside your project, so
editing a stylesheet re-runs the asset build and regenerates the site. The
`watch` paths are resolved relative to the project root and may point outside it
(e.g. `"../design/src"` for a shared design repo).

This is the one piece of CLI configuration Kiln reads from a file — a *tooling*
concern, separate from your Swift-defined site config. With no `kiln.json`,
behaviour is unchanged; override or skip the step per-run with `--pre-build
<cmd>` / `--no-pre-build`.

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

### Writing direction (RTL)

Each `Language` has an `isRTL` flag that drives the `dir` attribute on the page
(`<html lang="ar" dir="rtl">`). It defaults from the `LanguageCode` — `.arabic`
and `.hebrew` are right-to-left, everything else is left-to-right — and is exposed
to templates as `#(language.direction)` (`"rtl"`/`"ltr"`) and `#(language.isRTL)`.
For a locale Kiln can't classify, set it explicitly:

```swift
Language(.custom(code: "fa", name: "فارسی"), isRTL: true)
```

When an RTL page falls back to the (LTR) default language because a translation is
missing, the default theme wraps just that content in `dir="ltr"` — so the page
chrome stays RTL while the untranslated prose still reads naturally. The theme's
CSS is written with logical properties so it mirrors without a separate stylesheet;
code blocks are kept LTR regardless of page direction.

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
| `url`             | `String`              | Canonical site URL. With `basePath` set, this is the scheme + host (e.g. `"https://example.com"`). |
| `basePath`        | `String`              | Subdirectory the site is served under (e.g. `"/docs"`). Empty by default (served from the domain root). Prefixed onto every generated root-relative link so they resolve in the subpath. |
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
| `docc`            | `DocCSite?`           | An API-reference site built from DocC archives (see [API reference (DocC)](#api-reference-docc)). |

### Serving from a subdirectory (`basePath`)

By default Kiln assumes the site is served from the **domain root**, so every
generated link is root-absolute (`/_kiln/css/theme.css`, `/guides/routing/`, …).
If you deploy under a subdirectory instead (e.g. `https://example.com/docs/`),
set `basePath` so those links resolve in the subpath:

```swift
let site = KilnSite(
    name: "My Docs",
    url: "https://example.com",   // scheme + host only — NOT "https://example.com/docs"
    basePath: "/docs",            // the subdirectory; "docs", "/docs", "/docs/" all work
    // …
)
```

> [!IMPORTANT]
> When `basePath` is set, `url` must be the **scheme + host only**
> (`"https://example.com"`), *not* including the subpath. Kiln builds absolute
> URLs (canonical, `og:url`, sitemap, `llms.txt`) by joining `url` with the
> base-path-prefixed page path — so putting the subpath in **both** `url` and
> `basePath` double-prefixes them (`https://example.com/docs/docs/page/`).

A few more things to know:

- **Output layout is unchanged.** `basePath` is a *serving* prefix, not an output
  directory — the build still writes `index.html`, `_kiln/…`, etc. at the root of
  the output folder. Deploy that folder *into* your server's subdirectory.
- **Hand-written absolute links are left alone.** A Markdown link to `/foo` is
  emitted verbatim (matching MkDocs). Use relative links (`../foo.md`) — which
  Kiln rewrites with the base path — if you need them to follow the subpath.
- **Local preview:** `kiln serve --base-path /docs` strips the prefix so the
  preview at `http://127.0.0.1:8080/docs/` mirrors production.

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
`searchIndexURL`, and `basePath` (prefix every hard-coded root-relative link —
e.g. `#(basePath)/_kiln/css/theme.css` — so custom themes work under a subpath).
The rendered page body is injected with `#unsafeHTML(page.content)`.

## Search

A search index (`search/search_index.json`) is generated per language at build
time. The bundled theme includes a small, dependency-free client that fetches
the index and ranks results in the browser — no external search service and no
build-time JavaScript toolchain required. Tokenisation is Unicode-aware: accented
Latin scripts are matched whole, and Han/kana (which aren't space-separated) are
segmented into bigrams so CJK queries work.

## API reference (DocC)

Kiln can host **API reference documentation** generated by
[DocC](https://www.swift.org/documentation/docc/) — the docs Xcode and the Swift
toolchain produce from your source. Point Kiln at a set of pre-built DocC
archives and it renders them into *your* theme as one cohesive site: a catalog
landing page, a module switcher, a per-package version switcher, and sitewide
search — the setup behind [api.vapor.codes](https://api.vapor.codes), which hosts
many Vapor packages side by side.

### How it works: two stages

Kiln does **not** compile your packages or shell out to the Swift toolchain. The
pipeline is deliberately split in two:

1. **Stage A — build the archives (outside Kiln).** For each package/version, run
   DocC to emit a `.doccarchive`:

   ```sh
   swift package --allow-writing-to-directory ./out \
     generate-documentation --target MyLib --output-path ./out/MyLib.doccarchive
   ```

   This is the only step that needs the package's source and toolchain, so it's
   typically done in CI (once per release) and cached.

2. **Stage B — render (Kiln).** Kiln reads the machine-readable render JSON inside
   each archive and renders themed HTML. The only coupling is DocC's render-JSON
   schema, which is versioned and additive, and Kiln decodes it leniently — an
   unrecognised construct degrades gracefully and surfaces a build warning rather
   than failing the build.

Drop the archives under your content directory using the layout
`<archivesDirectory>/<versionID>/<Module>.doccarchive` (default
`archivesDirectory` is `archives`, and a single-version package uses the version
id `default`):

```
Content/
└── archives/
    ├── default/
    │   ├── MyLib.doccarchive
    │   └── MyLibTesting.doccarchive
    └── 5-alpha/               # a non-default version of the same package
        └── MyLib.doccarchive
```

The raw archives are read at build time and are **not** copied into the output
(only the assets they reference — images, videos, downloads — are).

### Configuration

Set `KilnSite.docc` to a `DocCSite`. Each `APIPackage` is one git repository (the
checkout unit) that owns an independent set of `PackageVersion`s, each declaring
the `Module`s it ships. A package's target set can change across major versions,
so modules live on the version — extract them into variables and reuse them
across the versions that share them:

```swift
let myLib = Module("MyLib", description: "The core library.")
let myLibTesting = Module("MyLibTesting", title: "Testing", group: "Testing")

let site = KilnSite(
    name: "MyLib API Docs",
    url: "https://api.mylib.dev",
    description: "API reference for MyLib.",
    theme: .default(palette: .autoLightDark(primary: .black, accent: .blue)),
    docc: DocCSite(
        packages: [
            // A package with two version lines → a version switcher. v6 drops the
            // testing target, so it lists a different module set.
            APIPackage(
                "me/mylib",
                group: "Core",
                versions: [
                    PackageVersion("5", name: "5.x", ref: "main", isDefault: true, modules: [myLib, myLibTesting]),
                    PackageVersion("4", name: "4.x", ref: "release/4.x", modules: [myLib, myLibTesting]),
                    PackageVersion("6-alpha", name: "6.0 (alpha)", ref: "future", isPrerelease: true, modules: [myLib]),
                ]
            ),
            // Single-version shorthand: `PackageVersion.single(ref:modules:)`
            // builds one default version served at the module root.
            APIPackage("me/mylib-extras", group: "Core", versions: [
                .single(ref: "main", modules: [Module("MyLibExtras", description: "Optional add-ons.")]),
            ]),
        ],
        // Order of the section groups on the catalog page and in the switcher.
        groupOrder: ["Core", "Testing"]
    )
)
```

| Type / field | Notes |
| --- | --- |
| `DocCSite(packages:groupOrder:archivesDirectory:)` | The API-reference site. `groupOrder` orders the catalog/switcher sections (unlisted groups sort after; ungrouped modules fall into `Other`). `archivesDirectory` defaults to `archives`. |
| `APIPackage(_ repo, group:, versions:)` | One git repo. `repo` is `"owner/name"`. `group` is a default group for its modules. Modules are declared per `PackageVersion`, not on the package. |
| `PackageVersion(_ id, name:, ref:, isDefault:, isPrerelease:, deprecated:, prereleaseLabel:, modules:)` | A version line and the `Module`s it ships. `id` is the URL segment (URL-safe, unique per package); `name` is the switcher label; `ref` is the git branch/tag Stage A builds. Exactly one version per package is the default and it must not be a pre-release. A pre-release shows a badge (in the switchers and on catalog cards) taken from `prereleaseLabel`, else inferred from the id/name as `alpha`/`beta`/`rc` (default `beta`). `PackageVersion.single(ref:modules:)` is shorthand for a lone default version. |
| `Module(_ name, title:, group:, description:, image:)` | A DocC target. `name` keys the archive and the URL and must be unique across the whole site; `title` overrides the display name; `group` overrides the package group; `description` is the catalog-card blurb; `image` is an optional logo shown on the module's landing page (a site-relative asset path or an absolute URL). |

The configuration is validated at build time (unique repos, unique module names
sitewide, exactly one non-pre-release default version per package, URL-safe
version ids, …); a `DocCConfigurationError` describes any problem.

### URL scheme

URLs are **module-first**, and DocC's own `/documentation/<module>` prefix is
stripped. The default version is served at the module root; other versions live
under their id:

```
/mylib/                                  # MyLib landing (default version)
/mylib/somestruct/                       # a symbol
/mylib/somestruct/dosomething(_:)/       # a member
/mylib/4/                                # the 4.x version's landing
/mylib/6-alpha/somestruct/               # the 6.0-alpha version's symbol
/                                        # the generated catalog landing page
```

The **catalog landing page** at the site root lists every module, grouped by
`group` in `groupOrder`. Every page carries a **module switcher** (jump to any
module) and, for multi-version packages, a **per-package version switcher**, both
in the sidebar.

### Search, SEO, and AI indexes

- **Sitewide search** works from any page and covers every module — but only the
  **default version** of each package is indexed (non-default versions are
  excluded to keep the index focused).
- Non-default version pages are marked `noindex` for crawlers.
- With `llmsText: true`, `llms.txt` is a compact **module index** (grouped like
  the catalog) — no full corpus, since an API surface is large and better crawled
  on demand.

### Building

A DocC site builds like any Kiln site once the archives are in place:

```sh
swift run          # or: kiln build
kiln serve         # preview at http://127.0.0.1:8080
```

Rendering a large multi-package API can be slow, so pass `incremental: true` to
reuse output for packages whose archives are unchanged since the last build:

```swift
try await Kiln.build(site, contentDirectory: "Content",
                     outputDirectory: "site", incremental: true)
```

A fresh checkout has no previous build to reuse, so CI still does a full build;
incremental only helps repeated local builds.

Kiln can also drive Stage A for you: `Kiln.buildDocCArchives(site,
contentDirectory:)` checks out each configured package at its ref and runs
`swift package generate-documentation`, dropping the archives in place (archives
that already exist are reused; pass `rebuild:` to force). Call it before
`Kiln.build` for a single command that produces archives *and* the site — see
[`Examples/APIDocsSite`](Examples/APIDocsSite), which builds Kiln's own API
reference this way.

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

[`Examples/APIDocsSite`](Examples/APIDocsSite) is the DocC counterpart —
**Kiln's own API reference**, built with the [DocC support](#api-reference-docc).
Its `swift run` performs both stages: `Kiln.buildDocCArchives` generates the
archives (first run only), then `Kiln.build` renders them. It declares two
version lines so the module/version switchers, pre-release badges, and the
catalog page all render.

## Development

```sh
swift build
swift test
```

CI builds and tests on both macOS and Linux and verifies the example site builds
on every push to `main` and every pull request.

## License

MIT. See [LICENSE](LICENSE).
