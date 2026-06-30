# Handoff: Vapor design-system consolidation on Kiln

## ⚠️ First: the work is UNCOMMITTED
All changes below live in working trees across **5 repos** and are **not committed**.
To continue on another machine you must bring those changes over (commit+push, or
sync the working trees). This document is *context*, not the code itself. The user
manages all commits/pushes/tags/releases/deploys manually — do not commit or push
unprompted.

Repo layout (paths on the origin machine; adjust the root for yours):
- Kiln engine: `~/Developer/BH/kiln`
- Sites: `~/Developer/Vapor/{design,website,blog,docs}`

## Goal
The Vapor docs/blog/website are all on the **Kiln** static site generator
(Swift; Leaf templates). Each site had hand-copied duplicates of the shared chrome
(header/footer/cards/pagination). Consolidate those into ONE set of shared Leaf
partials shipped from the **design** repo as a SwiftPM resource and consumed as a
Kiln "theme layer". CSS/JS stays on the `design.vapor.codes` CDN (decided) — only
Leaf templates move into the shared package. Also added two Kiln engine features.

## ✅ DONE (all verified)

### Kiln engine (`~/Developer/BH/kiln`)
1. **Shared theme layers.** `Theme.sharedLayers: [URL]` added
   (`Sources/Kiln/Configuration/Theme.swift`, needs `public import Foundation`),
   threaded through `resolveTheme()` in `Sources/Kiln/Site/SiteGenerator.swift`
   (+ new `ThemeError.sharedLayerDirectoryNotFound`). Resolution order:
   site `Theme/` dir → shared layers → bundled default (templates first-wins;
   assets last-wins). Tests: `Tests/KilnTests/SharedThemeLayerTests.swift`.
2. **npm/asset build hook.** New `Sources/CLI/PreBuildConfig.swift` reads optional
   `kiln.json` `{ "preBuild": { "command": "...", "watch": [...] } }`.
   `ProcessRunner.runCommand` (new) streams+captures output. `--pre-build` /
   `--no-pre-build` flags on `build` & `serve`; `serve` runs a `fullBuild()`
   (prebuild→swift) on initial build + on watch. `DirectoryWatcher` gained
   `additionalRoots`, ignores `node_modules`, and re-baselines AFTER each build
   (prevents asset-output infinite loops). Tests: `Tests/KilnTests/PreBuildTests.swift`.
   Docs updated: `Examples/ExampleSite/Content/latest/guides/theming.md` +
   `getting-started/cli.md`.
3. **Pagination localisation.** `Sources/Kiln/Blog/BlogLeafData.swift`
   `pagination()` now emits `previousLabel`/`nextLabel`; threaded through
   `listing()` + `authorPage()` and the 3 call sites in
   `SiteGenerator.renderBlog` (pass `language.localisation.resolved.previousPage/.nextPage`).
   `swift test` → **121 tests pass**.

### Design package (`~/Developer/Vapor/design`)
- `Package.swift`: new `VaporDesignTheme` library target + product,
  `resources: [.copy("Theme")]`, no deps beyond Foundation. (Existing Publish
  `DesignSite`/`VaporDesign` targets untouched.)
- `Sources/VaporDesignTheme/VaporDesignTheme.swift`: `VaporDesignTheme.directory`
  → `Bundle.module` URL of the bundled `Theme/` dir.
- `Sources/VaporDesignTheme/README.md`: documents partials + required custom strings.
- Shared partials in `Sources/VaporDesignTheme/Theme/templates/partials/`:
  - `footer.leaf` — port of Publish `SiteFooter`; links branch on `customStrings.siteId`.
  - `header.leaf` — port of `SiteNavigation`; MARKETING navbar (main+blog only);
    language picker auto-shows when `count(languages) > 1`.
  - `pagination.leaf` — port of Publish `Pagination`; reads `previousLabel`/`nextLabel`
    from its (scoped) context.
  - `blog-pagination.leaf` — one-liner `#extend("partials/pagination")` adapter so
    Kiln's blog feature (which extends `partials/blog-pagination`) reuses the shared one.
  - `author-card.leaf` — person/team card (avatar/name/handle/bio/socials).

### Blog (`~/Developer/Vapor/blog`) — adopted as the proof site
- `Package.swift`: switched Kiln to local path dep `../../BH/kiln`, added
  `../design` dep + `VaporDesignTheme` product.
- `Sources/Blog/main.swift`: `import VaporDesignTheme`; theme is
  `.custom(directory: "Theme", sharedLayers: [VaporDesignTheme.directory], palette: …)`;
  added `languages: [Language(.english, isDefault: true, customStrings: [...])]` with
  `siteId: "blog"`, the `footer.*` keys, and the `nav.*` keys.
- `Theme/templates/base.leaf`: wrapped header as
  `<header class="vapor-banner">#extend("partials/header")</header>` (banner is blog-only).
- Deleted blog's local `footer.leaf`, `header.leaf`, `blog-pagination.leaf`,
  `author-card.leaf` (now resolve from shared layer). Remaining blog-only partials:
  `blog-card`, `blog-share`, `blog-subscribe`.
- Verified: rendered footer/header/pagination/author-card are structurally identical
  to pre-refactor output (footer only differs by an intended `download` attr on the
  Press Kit link; pagination aria-label "blog-pagination"→generic "Pagination").

## Key decisions & gotchas (IMPORTANT)
- **CDN-only** for CSS/JS — shared partials reference `design.vapor.codes/main.css`+`main.js`.
  Only Leaf templates ship in the package.
- **`siteId` branching**: each site sets `customStrings["siteId"]` =
  `"main"|"blog"|"docs"|"apiDocs"`; shared partials point "owning-site" links
  internally and everything else to canonical absolute URLs (replaces the old
  Publish `CurrentSite` enum).
- **Docs header is NOT shared** — it's a different sidebar-shell component
  (`.kiln-navmenu`, `kiln-` classes, version + mobile-doc pickers, logo in sidebar).
  Shared header covers the marketing navbar (website + blog only).
- **LeafKit has NO comment syntax** — `<!-- -->` in a `.leaf` leaks into every page.
  Keep shared partials comment-free; document in the package README.
- **`#extend` context scoping** (verified in LeafKit source): `#extend("x")` with NO
  2nd arg inherits the FULL parent context; `#extend("x", obj)` REPLACES context with
  `obj` (so `strings.*`/`#localise` are unreachable inside). footer/header are
  unscoped → localise directly. pagination is scoped → labels travel in the
  view-model (Kiln injects `previousLabel`/`nextLabel`; website team page passes its own).
  author-card is scoped but data-only → fine.
- **Attribute quoting**: `aria-label="#localise("key")"` (double quotes w/ nested
  double quotes) parses fine and matches output — don't switch to single quotes.
- **Verify formatted partials with a WHITESPACE-NORMALISED diff** (templates are
  pretty-printed now, so byte-diff won't match; normalise inter-tag whitespace).
- **Local path deps** are in use for blog↔kiln↔design during dev. The new Kiln
  features are UNRELEASED — website/docs adoption also needs local path deps until
  the user cuts a Kiln release + design-package release and swaps back to version pins.

## ⏭️ TODO (in rough order)
1. **Shared `base.leaf`** — the `<head>`/meta/CDN-link skeleton (~90% identical
   across sites). Hardest because of site-gated sections: blog article OG tags,
   docs sidebar/TOC chrome, website home-page body class + scripts. Likely a shared
   skeleton + context-gated/`#if` sections, with docs possibly keeping its own.
2. **Adopt shared layer in website + docs** (same recipe as blog):
   - website: `siteId: "main"`, add `footer.*` + `nav.*` custom strings across its
     ~11 language files (`Sources/VaporWebsite/Translations/*.swift`), delete its
     duplicated footer/header partials. NOTE: user said a "team branch" on the
     website will use the new shared `pagination.leaf` + `author-card.leaf` — those
     were extracted FOR that; don't edit the website's team branch unprompted.
   - docs: `siteId: "docs"`, delete its duplicated footer (keep its own header/base
     sidebar chrome).
3. **Design site Publish→Kiln migration** — port `DesignSite` (the showcase/reference
   pages) off Publish to a Kiln site; drop the Publish dep; add a `kiln.json`
   (`{ "preBuild": { "command": "npm run build", "watch": ["src"] } }`) so
   `kiln serve` rebuilds webpack CSS/JS first. (The webpack output must NOT write
   into Kiln's `site/` output dir.)
4. **Release wiring (user does this)** — tag a Kiln release with the engine features
   + a design-package release; swap local path deps back to version pins.

## How to verify
- Kiln: `cd ~/Developer/BH/kiln && swift build && swift test` (expect 121 pass).
- Blog: `cd ~/Developer/Vapor/blog && swift run Blog` then inspect `site/index.html`
  (header/footer/pagination) and `site/authors/index.html` (author-card). Diff a
  rendered partial before/after with whitespace normalised.
- Pattern for verifying a newly-shared partial: capture the site's current rendered
  HTML for that component → extract it into the shared package → delete the site's
  local copy → rebuild → normalised-diff (should match modulo intended changes).

## Canonical sources for porting more partials
Publish components at `~/Developer/Vapor/design/Sources/VaporDesign/Components/`
(`SiteFooter.swift`, `SiteNavigation.swift`, `Pagination.swift`, `Blog/*`,
`MainSite/*`). The website's existing `Theme/templates/partials/header.leaf` is
already a clean parameterised port of `SiteNavigation` (main-site variant).
NOTE: the `MainSite/*` cards (PackageCard, ShowcaseCard, …) are website-only —
not cross-site chrome, don't extract them.
