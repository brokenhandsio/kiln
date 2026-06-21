---
description: SEO and social cards — canonical URLs, OpenGraph and Twitter tags, sitemap, and robots.txt.
image: assets/social-card.png
---
# SEO & Social Cards

Kiln aims to make the generated HTML as discoverable as possible, with no extra
work on your part. This page sets a custom `image` in its front matter, so when
it's shared the social preview uses that image.

## Per-page meta

For every page Kiln emits:

- a `<title>` (from the page heading or front-matter `title`),
- a `<meta name="description">` (front-matter `description`, falling back to the
  site description),
- a `<link rel="canonical">` pointing at the page's canonical URL,
- `hreflang` alternates for each language.

## OpenGraph & Twitter

OpenGraph and Twitter Card tags are generated for rich link previews:

```html
<meta property="og:type" content="article">
<meta property="og:title" content="SEO &amp; Social Cards">
<meta property="og:url" content="https://kiln.brokenhands.io/guides/seo/">
<meta property="og:image" content="https://kiln.brokenhands.io/assets/social-card.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:site" content="@brokenhandsio">
```

The preview image resolves in this order:

1. the page's front-matter `image`,
2. the site-wide `image`,
3. (none) — the card renders without an image.

!!! tip "Use a real raster image"
    Social scrapers (Slack, X, iMessage, …) handle PNG/JPG far more reliably
    than SVG, so set `image` to a `1200×630` PNG — like this site's
    `assets/social-card.png`.

## Sitemap & robots

Every build writes:

- `sitemap.xml` — all pages across all languages, with `hreflang` alternates,
- `robots.txt` — pointing at the sitemap.

```
Sitemap: https://kiln.brokenhands.io/sitemap.xml
```

## Verifying your domain

You don't need a special file for search-console verification — add the meta tag
your provider gives you via a [custom template](theming.md) or `extraCSS`/head
hook. Most teams use DNS verification instead, which needs nothing in the site.
