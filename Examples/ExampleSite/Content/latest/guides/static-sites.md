---
description: Build a plain static site — marketing pages, a landing page, a portfolio — not just versioned documentation.
---
# Static Sites

Kiln isn't only for versioned documentation. The same engine builds a plain
**static site** — a marketing site, a landing page, a portfolio — from a flat
set of markdown pages. You opt in simply by *not* declaring versions: give the
`KilnSite` a navigation closure of `Page`s and Kiln renders each one at a clean
URL.

```swift
import Kiln

let site = KilnSite(
    name: "Acme",
    url: "https://acme.example",
    description: "We make excellent widgets.",
    theme: .default(palette: .autoLightDark(primary: .black, accent: .blue))
) {
    Page("Home", "index.md")
    Page("Pricing", "pricing.md")
    Page("About", "about.md")
}

try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "site")
```

Each `Page(_:_:)` maps a navigation label to a markdown file under the content
directory. `index.md` becomes the site root (`/`); `pricing.md` becomes
`/pricing/`. There's no version prefix and no version switcher — the URLs stay
flat.

## Static site vs. versioned docs vs. blog

A `KilnSite` takes one of three shapes, decided entirely by which argument you
pass. Everything else — content, theming, SEO — is the same.

| You're building… | Configure | Example URLs |
| --- | --- | --- |
| A marketing/landing site | `navigation: { Page(...) }` | `/`, `/pricing/`, `/about/` |
| Docs with multiple released versions | `versions: [DocVersion(...)]` | `/`, `/2.0/`, `/0.9/` |
| A blog of dated posts | `blog: Blog()` | see [Blog](blog.md) |

A static site is the **default shape**: a `KilnSite` with neither `versions:`
nor `blog:` set. [vapor.codes](https://www.vapor.codes) itself is built this way.

## Everything else still applies

A static site shares the rest of Kiln unchanged — [theming](theming.md),
[search](search.md), [SEO & social cards](seo.md),
[link checking](link-checking.md), and [AI-friendly output](llms.md) all work
identically. Per-page front matter (title, `description`, `image`) is honoured
just as in docs; see [Content & Localisation](content-and-localisation.md).

## Localisation

A static site is multilingual the same way the rest of Kiln is: pass `languages:`
and translate a page with a locale suffix (`about.de.md`). Untranslated pages
fall back to the default language.

```swift
let site = KilnSite(
    name: "Acme",
    url: "https://acme.example",
    languages: [
        .init(.english, isDefault: true),
        .init(.german),
    ]
) {
    Page("Home", "index.md")
    Page("About", "about.md")
}
```

!!! tip "External links in the nav"
    A navigation closure can mix `Page`s with `Link`s to point at anything off
    the site — `Link("GitHub", "https://github.com/acme")`.
