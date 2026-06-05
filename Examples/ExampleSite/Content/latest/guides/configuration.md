---
title: Configuration Reference
description: Every option you can set on a KilnSite.
image: assets/social-card.svg
---

# Configuration

Everything about your site is described by a single `KilnSite` value. This page
uses a custom front-matter `title` (see the browser tab) to demonstrate the
`meta` feature.

## Fields

| Field             | Type                  | Notes |
| ----------------- | --------------------- | ----- |
| `name`            | `String`              | Site title. |
| `url`             | `String`              | Canonical site URL (used for sitemap, OpenGraph, hreflang). |
| `author`          | `String?`             | Used for meta tags. |
| `description`     | `String?`             | Default meta/OpenGraph description. |
| `image`           | `String?`             | Default social preview image (content-relative path). |
| `twitterSite`     | `String?`             | Handle for the `twitter:site` tag (e.g. `"@brokenhandsio"`). |
| `repository`      | `Repository?`         | `name`, `url`, optional `editURI` for "edit this page" links. |
| `copyright`       | `String?`             | Footer notice. |
| `theme`           | `Theme`               | `.default(…)` or `.custom(directory:…)` — see [Theming](theming.md). |
| `social`          | `[SocialLink]`        | Icon + link; shown in the header/footer. |
| `carbonAds`       | `CarbonAds?`          | [Carbon Ads](https://www.carbonads.net) `serve`/`placement`. |
| `extraCSS`        | `[String]`            | Extra stylesheets (content-relative). |
| `extraJavaScript` | `[String]`            | Extra scripts. |
| `languages`       | `[Language]`          | See [Content & Localisation](content-and-localisation.md). |
| `markdown`        | `MarkdownExtensions`  | Feature toggles + table-of-contents options. |
| `navigation`      | `@NavBuilder`         | The nav tree — see [Navigation](navigation.md). |

## A fuller example

```swift
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
    }
)

try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "site")
```

## Languages

Declare each language you support with a `LanguageCode` — a built-in case like
`.english` or `.german`, or `.custom(code:name:)`. Exactly one language must be
the default; missing translations fall back to it automatically.

```swift
languages: [
    .init(.english, isDefault: true),
    .init(.german, navTranslations: ["Guides": "Anleitungen"]),
    .init(.custom(code: "gd", name: "Gàidhlig")),
]
```

See [Content & Localisation](content-and-localisation.md) for the full story on
translations, fallback, and UI strings.

## Theme

```swift
theme: .default(
    palette: .autoLightDark(primary: .black, accent: .blue),
    logo: "assets/logo.svg",
    favicon: "assets/logo.svg"
)
```

`Color` accepts presets (`.black`, `.blue`, `.indigo`, …) or any CSS string via
`Color("#2f6feb")`. To replace the theme entirely, use `.custom(directory:)` and
see [Theming](theming.md).

!!! note "Logical paths"
    Navigation references the *default-language* file path
    (`guides/configuration.md`). Kiln finds the right translation per language
    for you — you never hard-code locale-suffixed paths.
