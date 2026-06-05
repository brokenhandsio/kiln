---
description: Markdown features — headings, code, tables, admonitions, and front matter.
---
# Markdown

Kiln renders markdown with [swift-markdown](https://github.com/apple/swift-markdown)
(CommonMark + GitHub-flavoured extensions). This page is also a live demo —
everything shown here is rendered by Kiln.

## Headings & table of contents

Every heading gets a GitHub-style slug `id` and a permalink anchor, and Kiln
builds an on-page table of contents from them automatically.

## Code blocks

Fenced code blocks are highlighted client-side with highlight.js:

```swift
struct Greeter {
    let name: String
    func greet() -> String { "Hello, \(name)!" }
}
```

Inline `code` works too.

## Tables

| Syntax        | Renders as     |
| ------------- | -------------- |
| `**bold**`    | **bold**       |
| `*italic*`    | *italic*       |
| `` `code` ``  | `code`         |

## Lists

- Unordered item
- Another item
  - Nested item

1. Ordered item
2. Second item

- [x] A completed task
- [ ] An open task

## Admonitions

MkDocs/Python-Markdown-style call-outs:

```markdown
!!! tip "Optional title"
    Body content, rendered as markdown.

??? note "Collapsible"
    Hidden until expanded (use `???+` to start expanded).
```

Rendered:

!!! tip "Optional title"
    Body content, rendered as markdown.

??? note "Collapsible"
    Hidden until expanded (use `???+` to start expanded).

Supported types include `note`, `tip`, `warning`, `danger`, `info`, and
`success`.

## Front matter

An optional YAML block at the top of a file (the `meta` extension) overrides
per-page metadata:

```markdown
---
title: Custom Page Title
description: Used for meta and social tags.
image: assets/custom-card.png   # per-page social preview image
template: landing               # override the Leaf template for this page
---
```

| Key           | Effect |
| ------------- | ------ |
| `title`       | Overrides the `<title>` and heading-derived page title. |
| `description` | Sets the meta/OpenGraph description for the page. |
| `image`       | Per-page social preview image (see [SEO & Social Cards](seo.md)). |
| `template`    | Renders the page with a different [Leaf template](theming.md). |

!!! note
    This very page sets no front matter, but
    [Configuration](configuration.md) sets a custom `title` — compare their
    browser tabs.

## Links & images

Standard markdown links and images work, and **intra-doc links between `.md`
files are rewritten** to the correct pretty, locale-aware URLs at build time —
see [Link Checking](link-checking.md). Relative image paths are resolved against
the page's location and copied into the output.
