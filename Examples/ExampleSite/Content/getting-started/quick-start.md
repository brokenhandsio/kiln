# Quick Start

This guide walks you through building your first site.

## 1. Create the configuration

```swift
import Kiln

let site = KilnSite(name: "My Docs", url: "https://example.com") {
    Page("Welcome", "index.md")
}
```

## 2. Write some markdown

Create `Content/index.md`:

```markdown
# Welcome

Hello, world!
```

## 3. Build

```swift
try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "public")
```

!!! success "That's it!"
    Your site is now in `public/`. Serve it with any static file server.

## Admonition gallery

!!! note
    This is a note.

!!! tip
    This is a tip.

!!! warning
    This is a warning.

!!! danger
    This is a danger callout.
