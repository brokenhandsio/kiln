---
description: Client-side, per-language search with Unicode-aware tokenisation — no external service.
---
# Search

Kiln generates a search index (`search/search_index.json`) **per language** at
build time. The bundled theme includes a small, dependency-free client that
fetches the index and ranks results in the browser.

- **No external service** — nothing to host or pay for, and it works offline.
- **No build-time JavaScript toolchain** — the index is produced by Kiln itself.
- **Per-language** — each language searches only its own content; the default
  language's content is indexed for pages that fall back.

!!! tip "Try it"
    Use the search box in the header of this site. It indexes every page,
    including this one.

## Unicode & CJK

Tokenisation is Unicode-aware:

- accented Latin scripts are matched whole (so a search without accents still
  finds accented words),
- Han/kana — which aren't space-separated — are segmented into bigrams, so CJK
  queries work.

## How fallback affects search

Because untranslated pages fall back to the default language (see
[Content & Localisation](content-and-localisation.md)), a language's search
index covers every page in the navigation — translated pages use their own text,
and fallback pages use the default-language text. Readers always get complete
results.

## Search features

Two opt-in theme features refine the experience:

```swift
theme: .default(features: [.searchSuggest, .searchHighlight])
```

| Feature            | Effect |
| ------------------ | ------ |
| `.searchSuggest`   | Show suggestions as you type. |
| `.searchHighlight` | Highlight the matched term on the destination page. |
