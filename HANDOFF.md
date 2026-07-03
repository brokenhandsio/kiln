# Handoff: Vapor design-system consolidation on Kiln

## Status / machine notes
The original cross-machine migration is **done**: the work below was committed to
its feature branches and is present on this machine. Newer work (the shared
`<head>`, see DONE §"Shared head") is **uncommitted** in the working trees. The
user manages all commits/pushes/tags/releases/deploys manually — do not commit or
push unprompted.

Repo layout **on this machine** (the origin machine used `~/Developer/BH/kiln`):
- Kiln engine: `~/Developer/BrokenHands/kiln`  (branch `shared-resources`)
- Sites: `~/Developer/Vapor/{design,website,blog,docs}`
  (branches: design `kiln-migration`, blog `shared-kiln`, website/docs `shared-design`)

Path-dep note: blog's `Package.swift` uses `.package(path: "../../BrokenHands/kiln")`
(was `../../BH/kiln` on the origin machine — fixed for this layout).

## Goal
The Vapor docs/blog/website are all on the **Kiln** static site generator
(Swift; Leaf templates). Each site had hand-copied duplicates of the shared chrome
(header/footer/cards/pagination). Consolidate those into ONE set of shared Leaf
partials shipped from the **design** repo as a SwiftPM resource and consumed as a
Kiln "theme layer". CSS/JS stays on the `design.vapor.codes` CDN (decided) — only
Leaf templates move into the shared package. Also added two Kiln engine features.

## ✅ DONE (all verified)

### Kiln engine (`~/Developer/BrokenHands/kiln`)
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
- `Package.swift`: switched Kiln to local path dep `../../BrokenHands/kiln`, added
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

### Shared head (the ENTIRE `<head>`) — done for blog + website, staged for docs
- New shared partials in `design/Sources/VaporDesignTheme/Theme/templates/partials/`:
  - `head.leaf` — the full `<head>`: charset, OG/Twitter cards, canonical, title,
    favicons, CSS/JS links, structured data. Consumed via `<head>#extend("partials/head")</head>`
    (unscoped → `#localise`/`customStrings`/`site.*`/`page.*` reachable).
  - `head-preconnect.leaf`, `head-brand.leaf` — preconnect hints + favicon/theme-color
    block; both consumed BY `head.leaf`.
- **NO Kiln engine changes** — all per-site variation is data:
  - `og:type` = `blogPost ? article : (isHome ? website : customStrings["head.defaultOgType"])`.
  - `<title>` from `head.homeSuffix` + `head.titleSeparator` + `page.frontMatter.titleKey`;
    long-title (>50 char) drops the suffix, applied **universally** (SEO).
  - extra CSS via `KilnSite(extraCSS:)`; RSS `<link>` gated on a dot-free `feedURL`
    custom string; website/docs-only metas gated and emit nothing for blog.
- **JS unified**: docs' local `theme-init.js` + the marketing sites' `detectColorScheme.js`
  collapse to ONE CDN script `design.vapor.codes/js/theme-init.js` (staged at
  `design/static/js/theme-init.js`; ⚠️ must be CDN-deployed before sites reference it live).
- Blog adopted (`blog/Theme/templates/base.leaf` head → `#extend("partials/head")`;
  `main.swift` adds the `head.*` + `feedURL` customStrings and `extraCSS:["static/css/blog.css"]`).
  Verified across 5 page types (home/post/author/tags/paginated): normalised-identical
  output except the one intended `detectColorScheme.js → theme-init.js` swap.
- Config contract documented in `VaporDesignTheme/README.md` ("Shared head").

### Website (`~/Developer/Vapor/website`) — adopted shared header/footer/head
- `Package.swift`: local `../../BrokenHands/kiln` path dep + `../design` + `VaporDesignTheme` product.
- `Sources/VaporWebsite/main.swift`: `import VaporDesignTheme`; theme gains
  `sharedLayers: [VaporDesignTheme.directory]`; added `twitterSite: "@codevapor"`
  (was hardcoded in the head) and `copyright: "© QuTheory, LLC 2026"` (footer reads `#(site.copyright)`).
- `Theme/templates/base.leaf`: inline `<head>` → `#extend("partials/head")`. Body
  unchanged (home `#if(page.isHome)` body-class + `updateStarsCount`/`scrollNavbar`/`scrollShowcase` scripts stay).
- Strings across the 11 `Translations/*.swift`:
  - Per-language `footer.tagline`/`footer.frameworkDocs`/`footer.apiDocs` (duplicated
    from each file's `home.hero.caption`/`nav.frameworkDocs`/`nav.apiDocs` via awk, to
    preserve localised footer output exactly).
  - English-only (fallback covers all): `siteId:"main"`, `nav.brandText:"Vapor"`,
    `head.defaultOgType:"website"`, `head.homeSuffix:""`, `head.titleSeparator:" | "`.
  - No `extraCSS` (site has no site-specific stylesheet), no `feedURL`.
- Deleted local `footer.leaf` + `header.leaf` (now resolve from shared layer).
- Verified (home/team/German, normalised): header + footer byte-identical incl.
  localised strings. Head deltas were all intended/superset:
  - intended: preconnect comment gone, `theme-init.js`, Press Kit `download`, `&copy;`→`©`.
  - additive metas: `og:image:alt`/`og:image:type`/`twitter:image:alt`.
  - **`robots:noindex` now emitted on the 50 non-English fallback pages** — the old
    head ignored Kiln's `noindex` (= `version.noindex || isFallback`,
    `RenderContext.swift:157`). KEPT per user: correct de-dup SEO, and self-corrects
    (a page stops being `isFallback` once it has real translated content → indexed again).
  - `<link rel="alternate" type="text/markdown">` per page — KEPT per user (`.md`
    files exist; `llmsText` left on).

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
- **LeafKit undefined-key behaviour** (verified in source): `#(x)`/`#if(x)` on a
  missing key → empty/false, NO error — so shared templates can reference the
  *superset* of all sites' fields. BUT `#for(x in y)` **throws** if `y` is undefined,
  so every loop must be over an always-present array (`languages`, `site.extraCSS`)
  or wrapped in `#if` (`#if(blogPost)`). This is what makes the shared `head.leaf`
  work with no per-site null-declarations.
- **Head is data-driven, not engine-driven**: everything divergent flows through
  existing context (`customStrings`/`#localise`, `page.frontMatter`, `site.extraCSS`,
  `site.twitterSite`). Do NOT add `RenderContext` fields for head variation.
- **theme-init.js CDN deploy**: the unified colour-scheme script is staged in
  `design/static/js/`. Sites reference `design.vapor.codes/js/theme-init.js`, which
  must be deployed to the CDN before it resolves live.
- **Local path deps** are in use for blog↔kiln↔design during dev. The new Kiln
  features are UNRELEASED — website/docs adoption also needs local path deps until
  the user cuts a Kiln release + design-package release and swaps back to version pins.

## ⏭️ TODO (in rough order)
1. **Shared `<head>` — DONE for blog + website** (see DONE §"Shared head"/"Website").
   Remaining: docs adopts it as part of its shared-layer adoption (TODO 2). The
   `<body>` is intentionally NOT shared (docs' sidebar shell, website's home
   body-class/scripts, blog's banner stay in each site's own `base.leaf`).
2. **Adopt shared layer (incl. `head.leaf`) in docs** (website is DONE — see DONE §"Website"):
   - docs: `siteId: "docs"`, `head.defaultOgType:"article"`, `head.homeSuffix:""`,
     `head.titleSeparator:" · "`, move `theme.css`/extras into `KilnSite(extraCSS:)`,
     delete its duplicated footer + inline head (keep its own header/base sidebar chrome).
     Its translated pages index correctly via the same `isFallback` noindex mechanic.
   - NOTE (website team branch): a "team branch" on the website will use the shared
     `pagination.leaf` + `author-card.leaf` — those were extracted FOR that; don't edit
     the website's team branch unprompted.
3. **Design site Publish→Kiln migration** — port `DesignSite` (the showcase/reference
   pages) off Publish to a Kiln site; drop the Publish dep; add a `kiln.json`
   (`{ "preBuild": { "command": "npm run build", "watch": ["src"] } }`) so
   `kiln serve` rebuilds webpack CSS/JS first. (The webpack output must NOT write
   into Kiln's `site/` output dir.)
4. **Release wiring (user does this)** — tag a Kiln release with the engine features
   + a design-package release; swap local path deps back to version pins.

## How to verify
- Kiln: `cd ~/Developer/BrokenHands/kiln && swift build && swift test` (expect 121 pass).
- Blog: `cd ~/Developer/Vapor/blog && swift run Blog` then inspect `site/index.html`
  (header/footer/pagination) and `site/authors/index.html` (author-card). Diff a
  rendered partial before/after with whitespace normalised.
- Website: `cd ~/Developer/Vapor/website && swift run VaporWebsite` then inspect
  `site/index.html`, `site/team/index.html`, `site/de/index.html`. Non-English pages
  should carry `robots:noindex` (fallbacks); English pages should not. NOTE: normalise
  BOTH `><` and `> <` when diffing (old head was minified, shared head is pretty-printed).
- Pattern for verifying a newly-shared partial: capture the site's current rendered
  HTML for that component → extract it into the shared package → delete the site's
  local copy → rebuild → normalised-diff (should match modulo intended changes).

## Canonical sources for porting more partials
Publish components at `~/Developer/Vapor/design/Sources/VaporDesign/Components/`
(`SiteFooter.swift`, `SiteNavigation.swift`, `Pagination.swift`, `Blog/*`,
`MainSite/*`). The shared `header.leaf` (in the design package) is the canonical
parameterised port of `SiteNavigation` (main-site variant) — the website's own
`header.leaf`/`footer.leaf` have now been deleted in favour of it.
NOTE: the `MainSite/*` cards (PackageCard, ShowcaseCard, …) are website-only —
not cross-site chrome, don't extract them.
