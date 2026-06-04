---
description: Validate internal links, anchors, and assets at build time — warn or fail the build.
---
# Link Checking

Broken links are the most common documentation bug. Kiln validates your internal
links against the **built** site, so you catch them before your readers do.

## What gets checked

- intra-doc links between `.md` files (including localised
  `content.de.md` targets),
- `#anchor` fragments (against the heading IDs Kiln generates),
- relative asset references (images, downloads).

External (`http(s)://`) links are left alone — checking those needs the network
and is better handled by a separate periodic job.

## Intra-doc link rewriting

You write ordinary relative markdown links between pages:

```markdown
See the [Configuration](configuration.md) guide, or jump to
[fallback](content-and-localisation.md#fallback).
```

At build time Kiln rewrites these to the correct **pretty, locale-aware** URLs
(`/guides/configuration/`, `/de/guides/configuration/`, …). The same source link
resolves to the right per-language destination automatically.

## Choosing the mode

Pass a `linkChecking` mode to the build:

```swift
// Warn (default): print issues, but still produce the site.
try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "site")

// Error: fail the build if any internal link is broken.
try await Kiln.build(
    site,
    contentDirectory: "Content",
    outputDirectory: "site",
    linkChecking: .error
)
```

| Mode      | Behaviour |
| --------- | --------- |
| `.warn`   | Print each issue; the build still succeeds. (Default.) |
| `.error`  | Print issues and throw `BrokenLinksError` — the build fails. |
| `.off`    | Skip link checking entirely. |

!!! tip "Use `.error` in CI"
    Run your build with `.error` in continuous integration so a broken link
    fails the pipeline, and keep `.warn` locally for fast iteration.
