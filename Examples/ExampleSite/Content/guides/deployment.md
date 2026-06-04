---
description: Build the static site and deploy it to any static host — GitHub Pages, Netlify, Cloudflare Pages, and more.
---
# Deployment

A Kiln build produces a plain directory of static files. There's no server
runtime, so you can host it anywhere that serves static content.

## What a build produces

```
site/
├── index.html                     # default language at the root
├── guides/configuration/index.html
├── de/                            # other languages under /<locale>/
│   ├── index.html
│   └── guides/configuration/index.html
├── search/search_index.json       # per-language search index
├── 404.html                       # per-language error pages
├── index.md                       # raw-markdown copy of each page
├── _kiln/                         # bundled theme assets (css/js)
├── sitemap.xml
├── robots.txt
├── llms.txt                       # AI/agent index
├── llms-full.txt
└── …                              # your content assets, copied as-is
```

URLs are "pretty" (directory-style): `/guides/configuration/` rather than
`/guides/configuration.html`.

## Build for production

```sh
kiln build --release
```

…or call the library directly in your executable. Either way, the output lands
in `site/` (by convention).

## Hosting

| Host                | How |
| ------------------- | --- |
| **GitHub Pages**    | Build in CI, push `site/` to the `gh-pages` branch (or use the Pages action with the artifact). |
| **Netlify**         | Build command runs your executable; publish directory is `site`. |
| **Cloudflare Pages**| Same — build command + `site` output directory. |
| **Any static host / S3 / nginx** | Upload the contents of `site/`. |

## Continuous deployment

A typical CI job:

```sh
swift run Docs          # or: kiln build --release
# deploy the ./site directory with your host's CLI/action
```

!!! tip "Fail on broken links in CI"
    Build with `linkChecking: .error` (see [Link Checking](link-checking.md)) so
    a broken internal link fails the deploy instead of shipping.

## Custom domain & canonical URL

Set `url` on your `KilnSite` to your final domain **before** deploying — it's
used for canonical URLs, `sitemap.xml`, OpenGraph tags, and hreflang alternates.
Configure the domain itself with your host (a `CNAME` for GitHub Pages, the
dashboard for Netlify/Cloudflare).
