import Kiln

// Kiln's API-reference site: the DocC documentation for the Kiln package
// itself, rendered by Kiln. This is the canonical example of a DocC site —
// a multi-package host (such as api.vapor.codes) is configured the same way,
// just with more `APIPackage`s.

// A module is a DocC target. `name` keys the archive on disk and the URL;
// the rest is presentation on the catalog page and in the module switcher.
let kiln = Module(
    "Kiln",
    description: "The site engine — configuration, content, theming, and DocC rendering.",
    image: "assets/logo.png"
)

let site = KilnSite(
    name: "Kiln API",
    url: "https://api.kiln.brokenhands.io",
    author: "Broken Hands",
    description: "API reference for Kiln, the Swift documentation-site generator.",
    theme: .default(
        palette: .autoLightDark(primary: .black, accent: .blue),
        logo: "assets/logo.svg",
        favicon: "assets/logo.svg"
    ),
    docc: DocCSite(
        packages: [
            // One git repository with two version lines, so the site exercises
            // the per-package version switcher, the pre-release badge, and the
            // pre-release banner. Both build from `main` here purely for the
            // demo — a real setup points each version at its own branch/tag.
            APIPackage(
                "brokenhandsio/kiln",
                group: "Kiln",
                versions: [
                    PackageVersion("1", name: "1.x", ref: "main", isDefault: true, modules: [kiln]),
                    PackageVersion("2-alpha", name: "2.0 (alpha)", ref: "main", isPrerelease: true, modules: [kiln]),
                ]
            ),
        ],
        groupOrder: ["Kiln"]
    )
)

let contentDirectory = "Content"
let outputDirectory = "public"

// Stage A: check out each package at its ref and run DocC, dropping the
// archives under Content/archives/<versionID>/. Archives that already exist
// are reused, so this is a no-op after the first run (CI would instead restore
// cached archives and pass `rebuild:` for the ones that changed).
print("Building DocC archives (first run clones + compiles, so it takes a while) …")
try Kiln.buildDocCArchives(site, contentDirectory: contentDirectory)

// Stage B: render the archives into a themed static site.
print("Building site into ./\(outputDirectory) …")
try await Kiln.build(site, contentDirectory: contentDirectory, outputDirectory: outputDirectory)
print("Done. Serve it with:  kiln serve --directory \(outputDirectory)")
