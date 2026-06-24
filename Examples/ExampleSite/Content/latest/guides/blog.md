---
description: Turn a directory of dated markdown posts into a blog — post pages, a paginated index, tags, authors, and an RSS feed.
---
# Blog

Kiln can build a **blog**: a directory of dated markdown posts, rendered as
individual post pages plus the listing pages a blog needs — a paginated index,
per-tag pages, author pages, and an RSS feed. It's the engine behind
[blog.vapor.codes](https://blog.vapor.codes).

A blog is **additive** to a `KilnSite`: posts are discovered by scanning a
directory, not declared in [navigation](navigation.md). Enable it by passing a
`Blog`:

```swift
import Kiln

let site = KilnSite(
    name: "Vapor",
    url: "https://blog.vapor.codes",
    description: "News and articles from the Vapor team.",
    blog: Blog()
)

try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "site")
```

!!! note "Single-language, unversioned"
    A site with a blog must be single-language and have no `versions:` — this
    keeps post URLs free of version and locale prefixes. The blog index *is* the
    site root, so a blog site has no `index.md`.

## Writing a post

Each `*.md` file in the posts directory (`posts/` by default, under your content
directory) becomes a post at `/posts/<filename>/`. The leading `# Heading`
becomes the title and is stripped from the body.

```markdown
---
date: 2024-09-03 09:00
description: A short summary used for cards, SEO, and the RSS feed.
tags: swift, release
author: tim
image: /images/posts/my-post.png
---
# My first post

Everything below the title is the post body…
```

| Front matter | Purpose |
| --- | --- |
| `date` | Publish date, parsed with the blog's `dateFormat`. Sorts posts newest-first. |
| `description` | Summary for cards, `<meta>` description, and the RSS feed. |
| `tags` | Comma-separated; each becomes a tag page. |
| `author` / `authorImageURL` | A single author (a registry [username](#authors) or a literal name). |
| `authors` / `authorImageURLs` | Semicolon-separated, for co-authored posts. |
| `image` | Per-post social/OpenGraph image (falls back to the site default). |

## What Kiln generates

From the posts directory Kiln produces:

| URL | Page |
| --- | --- |
| `/posts/<slug>/` | Each post. |
| `/`, `/2/`, … | Paginated index, newest-first. |
| `/tags/`, `/tags/<slug>/` | Tag directory and per-tag listings (paginated). |
| `/authors/`, `/authors/<slug>/` | Author directory and per-author listings (paginated). |
| `/feed.rss` | RSS 2.0 feed. |

Each post also carries `BlogPosting` + `BreadcrumbList` JSON-LD and is added to
the sitemap and [search index](search.md).

## Authors

Posts reference an author by `username` in front matter. Register authors on the
`Blog` to give them a name, photo, bio, and social links — Kiln then builds an
author page (`/authors/<username>/`) listing their posts, with `ProfilePage` /
`Person` JSON-LD:

```swift
blog: Blog(
    authors: [
        Author(
            username: "tim",
            name: "Tim",
            imageURL: "/author-images/tim.jpg",
            description: "Core team member.",
            github: "0xTim",
            mastodon: "https://hachyderm.io/@0xtim",
            website: "https://timc.dev"
        ),
    ]
)
```

A post with `author: tim` then links its byline to that author page (matching is
case-insensitive). The typed social fields — `github`, `twitter`, `mastodon`,
`bluesky`, `linkedin`, `instagram`, `website`, plus a `links:` array for
anything else — each render with the right icon. An `author:` value with no
registry match falls back to a plain display name.

## Configuration

`Blog()` works with sensible defaults; every option is overridable:

| Option | Default | |
| --- | --- | --- |
| `postsDirectory` | `"posts"` | Where post markdown lives, under the content dir. |
| `postsPerPage` | `8` | Posts per page on the index and tag/author listings. |
| `feedTitle` / `feedDescription` | site name / description | RSS channel metadata. |
| `indexTitle` | site name | Heading on the index. |
| `tagsTitle` / `authorsTitle` | `"Tags"` / `"Authors"` | Headings on the directories. |
| `dateFormat` | `"yyyy-MM-dd HH:mm"` | Parses each post's `date:` (fixed `en_US_POSIX`/UTC). |
| `displayDateFormat` | `"d MMMM yyyy"` | How dates render on pages and cards. |
| `readingWordsPerMinute` | `200` | Divisor for the reading-time estimate. |
| `authors` | `[]` | The [author registry](#authors). |

## Theming

The bundled theme ships templates for every blog page (`blog-post`,
`blog-index`, `blog-tags`, `blog-author`, and partials). Override any of them
with a [custom theme](theming.md) — drop a same-named `.leaf` file in your theme
directory and Kiln uses yours instead.
