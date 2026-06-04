---
description: Kiln generates llms.txt, llms-full.txt, and a raw-markdown copy of every page for AI tools and agents.
---
# AI-Friendly Output

Documentation is increasingly read by tools and agents, not just people. Kiln
generates machine-friendly output alongside the HTML, following the
[llmstxt.org](https://llmstxt.org) convention.

## What's generated

| File              | Contents |
| ----------------- | -------- |
| `llms.txt`        | An index: the site title, summary, and a curated list of page links (grouped by section). |
| `llms-full.txt`   | The full corpus — every page's markdown concatenated, with source markers. |
| `…/index.md`      | A raw-markdown copy of every page, sitting next to its `index.html`. |

## Per-page markdown alternate

Every HTML page advertises its markdown twin so tools can discover it:

```html
<link rel="alternate" type="text/markdown" href="/guides/llms.md">
```

So an agent can fetch the clean markdown source of any page by swapping the URL,
without scraping HTML.

## Example

`llms.txt` looks like this:

```text
# Kiln

> Kiln is a documentation-site generator written in Swift.

## Getting Started

- [Installation](https://kiln.brokenhands.io/getting-started/installation/index.md)
- [Quick Start](https://kiln.brokenhands.io/getting-started/quick-start/index.md)

## Guides

- [Configuration](https://kiln.brokenhands.io/guides/configuration/index.md)
```

## Toggling it

AI output is on by default. Turn it off with:

```swift
KilnSite(name: "My Docs", url: "https://example.com", llmsText: false) { … }
```

!!! note
    The index uses your navigation structure and the site description, so the
    better organised your nav and the clearer your `description`, the more useful
    `llms.txt` is.
