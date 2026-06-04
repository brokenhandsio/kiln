---
description: Customise Kiln's default theme with palette, logo, and fonts, or bring your own Leaf templates.
---
# Theming

Kiln ships a fresh, responsive default theme as a package resource: light/dark
colour schemes, a sidebar nav, an on-page table of contents, and search. You can
tweak it with options, or replace any part with your own templates.

## Tweaking the default theme

```swift
theme: .default(
    palette: .autoLightDark(primary: .black, accent: .blue),
    logo: "assets/logo.svg",
    favicon: "assets/logo.svg",
    fonts: .init(text: "Inter", code: "JetBrains Mono"),
    features: [.backToTop, .searchHighlight]
)
```

| Option     | Purpose |
| ---------- | ------- |
| `palette`  | `Palette` with `primary`/`accent` `Color`s and a default mode (`.auto`/`.light`/`.dark`). |
| `logo`     | Header logo (content-relative path). |
| `favicon`  | Site favicon. |
| `fonts`    | `Fonts(text:code:)` for body and code text. |
| `features` | Opt-in extras: `.searchSuggest`, `.searchHighlight`, `.navigationTabs`, `.backToTop`. |

`Color` has presets (`.black`, `.blue`, `.indigo`, …) or accepts any CSS string
via `Color("#2f6feb")`.

## Bringing your own templates

To customise the markup, point Kiln at a directory of your own
[Leaf](https://github.com/vapor/leaf-kit) templates and assets:

```swift
theme: .custom(directory: "Theme")
```

Templates resolve from **your directory first** and fall back to the bundled
theme, so you only override what you need. The theme is split into small
partials:

```
Theme/
├── templates/
│   ├── base.leaf            # overall page shell (<head>, header, layout, scripts)
│   ├── page.leaf            # a standard documentation page
│   ├── home.leaf            # the home page
│   ├── 404.leaf             # the error page
│   └── partials/
│       ├── header.leaf
│       ├── footer.leaf
│       ├── nav-tree.leaf
│       ├── toc.leaf
│       ├── search.leaf
│       ├── language-switcher.leaf
│       └── social-icons.leaf
├── css/
└── js/
```

## Template context

Templates receive a context with `site`, `page`, `nav`, `language`, `languages`,
and `searchIndexURL`. The rendered page body is injected with
`#unsafeHTML(page.content)`.

!!! tip "Per-page templates"
    A page can opt into a different template via the `template` front-matter key
    (see [Markdown](markdown.md)) — handy for a landing page or a differently
    laid-out reference.

## Extra CSS / JS

For small additions you don't need a full custom theme — just add stylesheets or
scripts (content-relative paths):

```swift
extraCSS: ["assets/custom.css"],
extraJavaScript: ["assets/custom.js"]
```
