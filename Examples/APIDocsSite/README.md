# APIDocsSite

Kiln's own API reference, built with Kiln's [DocC support](../../README.md#api-reference-docc):
DocC documents the `Kiln` module, and Kiln renders the resulting archive into a
themed static site with a catalog page, module/version switchers, and search.

This is the DocC counterpart to [ExampleSite](../ExampleSite) (the
markdown-guides site). A multi-package host like api.vapor.codes is configured
exactly the same way, with more `APIPackage`s.

## Building

```sh
swift run     # builds the archives (first run only), then renders ./public
kiln serve    # preview at http://127.0.0.1:8080
```

The executable runs both stages of the DocC pipeline:

- **Stage A** — `Kiln.buildDocCArchives` checks out `brokenhandsio/kiln` at each
  configured ref (into `.build/docc-sources/`), runs
  `swift package generate-documentation`, and drops the archives under
  `Content/archives/<versionID>/`. Archives that already exist are reused, so
  after the first run this is a no-op. It clones from GitHub and compiles the
  package, so the first run needs network access and a few minutes.
- **Stage B** — `Kiln.build` reads the archives and renders the site into
  `./public`. This stage never touches git or the toolchain.

The site declares two version lines for the package (`1.x` as the default and a
`2.0 (alpha)` pre-release) so the version switcher, pre-release badge, and
pre-release banner all render. Both build from `main` purely for the demo — a
real setup points each version at its own branch or tag.

The generated `Content/archives/` and `public/` directories are gitignored.
