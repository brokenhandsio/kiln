---
description: Organise content, translate pages with locale-suffixed filenames, and fall back to the default language.
---
# Content & Localisation

Content is plain markdown under your content directory (`Content/` by
convention). The directory structure is up to you; navigation references files
by their path.

## Translations

Translations use a **locale suffix** on the filename:

```
Content/
├── index.md          # default language (e.g. English)
├── index.de.md       # German translation of the home page
└── guides/
    ├── configuration.md
    └── configuration.de.md
```

`index.md` and `index.de.md` share the same **logical path** (`index.md`), which
is what navigation references. You never put the locale in a `Page(...)` path —
Kiln resolves the right file per language.

## Fallback

When a page has no translation for a language, Kiln falls back to the default
language's content and shows a small "translation unavailable" banner — the
equivalent of mkdocs-static-i18n's `fallback_to_default: true`.

!!! note "Try it"
    Most pages on this very site aren't translated into German. Switch the
    language with the picker in the header and you'll see the fallback banner in
    action, with the navigation and UI fully localised around the English body.

The default language is built at the site root; other languages live under
`/<locale>/`:

```
site/
├── index.html              # default language
├── de/
│   └── index.html          # German
└── …
```

## Interface strings

The theme's own UI strings (search box, navigation labels, error page, …) are
localised per language via `LocalisationConfiguration`. Any string left unset
falls back to Kiln's built-in English default:

```swift
.init(.german, localisation: .init(
    searchPlaceholder: "Suchen",
    searchNoResults: "Keine Ergebnisse gefunden",
    tableOfContentsTitle: "Auf dieser Seite",
    previousPage: "Zurück",
    nextPage: "Weiter",
    editPage: "Diese Seite bearbeiten",
    notFoundTitle: "Seite nicht gefunden"
    // … and more; see LocalisationConfiguration
))
```

## Navigation labels & site name

Section and page titles are translated per language via each `Language`'s
`navTranslations` map (keyed on the default-language title), and a language can
override the whole `siteName`:

```swift
.init(
    .german,
    siteName: "Meine Doku",
    navTranslations: ["Guides": "Anleitungen", "Welcome": "Willkommen"]
)
```

## hreflang & the language switcher

For every page, Kiln emits `<link rel="alternate" hreflang="…">` tags for each
language and renders a language switcher in the header, so search engines and
readers can find the right translation.
