---
description: Build the navigation tree with the Page, Section, and Link result-builder DSL.
---
# Navigation

The navigation tree is built with a Swift result builder using three helpers:

```swift
navigation: {
    Page("Welcome", "index.md")          // a markdown page
    Section("Guides") {                   // a collapsible group
        Page("Configuration", "guides/configuration.md")
        Page("Theming", "guides/theming.md")
    }
    Link("API Reference", "https://example.com/api")  // an external link
}
```

## The three building blocks

| Helper | Purpose |
| ------ | ------- |
| `Page(_ title:, _ path:)`   | A markdown page. `path` is relative to the content directory (the *logical* path — no locale suffix). |
| `Section(_ title:) { … }`   | A named, collapsible group of pages and/or nested sections. |
| `Link(_ title:, _ url:)`    | An external link rendered in the nav. |

Sections can nest, so you can build multi-level navigation:

```swift
Section("Guides") {
    Page("Overview", "guides/index.md")
    Section("Advanced") {
        Page("Theming", "guides/theming.md")
    }
}
```

## Logical paths

A `Page` path always points at the **default-language** file, e.g.
`guides/configuration.md`. Kiln resolves the correct translation
(`guides/configuration.de.md`) per language automatically — see
[Content & Localisation](content-and-localisation.md).

## What Kiln derives for you

From this single tree Kiln computes, for every page and language:

- the **active trail** (which section/page is highlighted),
- **previous / next** links following document order, and
- **breadcrumbs** and the on-page table of contents.

## Pages outside the navigation

Some pages belong on the site but not in the sidebar — a legal notice, a privacy
policy, a landing page you link to from a campaign. Declare those as
`unlistedPages` instead of `Page` entries:

```swift
KilnSite(
    name: "Kiln",
    url: "https://kiln.brokenhands.io",
    unlistedPages: [
        UnlistedPage("Legal", "legal.md"),
        UnlistedPage("Draft", "draft.md", searchable: false, indexed: false),
    ]
) {
    Page("Welcome", "index.md")
    Section("Guides") { … }
}
```

On a versioned site, `unlistedPages` goes on the `DocVersion` instead — each
version has its own, exactly like `navigation`.

An unlisted page is built like any other: the full theme, "pretty" URL,
translations (`legal.de.md`), link checking, and an `<h1>`-derived title. It's
simply absent from the navigation tree, from the previous/next reading order,
and from `llms.txt` (which mirrors the navigation).

!!! note
    A markdown file that appears in *neither* the navigation nor `unlistedPages`
    isn't built at all. Declaring pages explicitly is what stops stray drafts in
    your content directory from being published by accident.

Two flags control how discoverable an unlisted page is:

| Flag | Default | Effect when `false` |
| ---- | ------- | ------------------- |
| `searchable` | `true` | Left out of the client-side [search](search.md) index. |
| `indexed`    | `true` | Left out of `sitemap.xml` and `llms-full.txt`, and rendered with `<meta name="robots" content="noindex">`. |

The defaults suit a footer page you *want* found — a legal or privacy page.
Setting both to `false` gives a page reachable only by direct link.

This site has one: the **[Legal](../legal.md)** page linked in the footer. It's
not in the sidebar, but it's a normal page in every other respect.

## Translating labels

Section and page titles are translated per language with each `Language`'s
`navTranslations` map, keyed on the default-language title:

```swift
.init(.german, navTranslations: [
    "Guides": "Anleitungen",
    "Configuration": "Konfiguration",
])
```

!!! tip
    Only titles you include in `navTranslations` are translated; anything left
    out simply shows in the default language. There's no need to translate every
    label at once.
