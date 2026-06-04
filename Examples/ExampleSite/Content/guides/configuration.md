---
title: Configuration Reference
description: Every option you can set on a KilnSite.
image: assets/logo.svg
---

# Configuration

Everything about your site is described by a `KilnSite` value. This page uses a
custom front-matter title (see the browser tab) to demonstrate the `meta`
feature.

## Languages

Declare each language you support. Exactly one must be the default; missing
translations fall back to it automatically.

```swift
languages: [
    .init(locale: "en", name: "English", isDefault: true),
    .init(locale: "de", name: "Deutsch", navTranslations: ["Guides": "Anleitungen"]),
]
```

## Navigation

The navigation tree is built with a result builder:

```swift
navigation: {
    Page("Welcome", "index.md")
    Section("Guides") {
        Page("Configuration", "guides/configuration.md")
    }
    Link("API Reference", "https://example.com/api")
}
```

!!! note "Logical paths"
    Navigation references the *default* file path (`guides/configuration.md`).
    Kiln finds the right translation per language for you.

## Theme

```swift
theme: .default(
    palette: .autoLightDark(primary: .black, accent: .blue),
    logo: "assets/logo.svg"
)
```
