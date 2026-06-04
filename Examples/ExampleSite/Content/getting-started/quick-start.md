---
description: Scaffold, build, and preview your first Kiln documentation site.
---
# Quick Start

This guide gets you from nothing to a live-previewing docs site.

## 1. Scaffold a project

The quickest path is the CLI:

```sh
kiln new my-docs
cd my-docs
```

`kiln new` prompts for a site name, URL, and languages, then writes a ready-to-build
SwiftPM project:

```
my-docs/
├── Package.swift
├── Content/
│   └── index.md
└── Sources/
    └── MyDocs/
        └── main.swift
```

??? info "Prefer to do it by hand?"
    Create a SwiftPM executable, add the `Kiln` dependency (see
    [Installation](installation.md)), and write the two files below yourself.
    The CLI just saves you the boilerplate.

## 2. Configure the site

`Sources/MyDocs/main.swift` is the single source of truth for your site:

```swift
import Kiln

let site = KilnSite(name: "My Docs", url: "https://example.com") {
    Page("Welcome", "index.md")
    Section("Guides") {
        Page("Configuration", "guides/configuration.md")
    }
}

try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "site")
```

See the [Configuration](../guides/configuration.md) reference for every option.

## 3. Write some markdown

Content is plain markdown under `Content/`. Create `Content/index.md`:

```markdown
# Welcome

Hello, world!
```

The path you give a `Page(...)` is the file's path relative to the content
directory — see [Navigation](../guides/navigation.md).

## 4. Preview it

```sh
kiln serve
```

This builds the site and serves it at <http://127.0.0.1:8080>, rebuilding
whenever you edit a file. Reload your browser to see changes.

!!! success "That's it!"
    When you're ready to publish, run `kiln build` and deploy the `site/`
    directory to any static host — see [Deployment](../guides/deployment.md).

## Admonition gallery

Kiln supports MkDocs-style admonitions out of the box:

!!! note
    This is a note.

!!! tip
    This is a tip.

!!! warning
    This is a warning.

!!! danger
    This is a danger callout.

??? note "Collapsible"
    Use `???` for a collapsed admonition, or `???+` to start it expanded.
