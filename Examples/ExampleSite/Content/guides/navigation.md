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
