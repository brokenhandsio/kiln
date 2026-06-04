# Welcome to Kiln

**Kiln** is a documentation site generator written in Swift. You define your
site in a type-safe Swift configuration and Kiln turns a directory of markdown
into a fast, modern static website.

!!! tip "New here?"
    Head to the [Installation](getting-started/installation.md) guide to get up
    and running in a couple of minutes.

## Why Kiln?

- **Swift all the way down** — configure everything in Swift, no YAML required.
- **Localised** — first-class multi-language support with fallback to your
  default language.
- **Themeable** — ship with a fresh default theme, or bring your own Leaf
  templates.
- **Searchable** — a client-side search index is generated for every language.

## A quick taste

```swift
let site = KilnSite(name: "My Docs", url: "https://example.com") {
    Page("Welcome", "index.md")
    Section("Guides") {
        Page("Configuration", "guides/configuration.md")
    }
}

try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "public")
```

| Feature        | Status        |
| -------------- | ------------- |
| Markdown       | ✅ Supported  |
| Admonitions    | ✅ Supported  |
| Localisation   | ✅ Supported  |
| Versioning     | 🚧 Planned    |

!!! warning
    Kiln is under active development. APIs may change before the 1.0 release.
