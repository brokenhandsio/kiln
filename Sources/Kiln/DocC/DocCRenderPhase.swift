import Foundation

/// The additive build phase that renders a ``DocCSite``'s pre-built archives into
/// themed Kiln pages — the DocC analogue of the blog phase.
///
/// For every module of every version of every package it: locates the archive
/// under `archivesDirectory`, loads it (``DocCArchiveLoader``), and renders each
/// page through ``DocCRenderer`` (with a cross-module link mapper from
/// ``DocCModuleRegistry``) into the shared page template. Missing archives,
/// per-page decode failures, and unhandled render-JSON constructs are collected
/// as warnings rather than failing the build.
struct DocCRenderPhase {
    let site: KilnSite
    let docc: DocCSite
    let contentDirectory: URL
    let outputDirectory: URL
    let basePath: String

    struct Result: Sendable {
        var warnings: [String] = []
        /// The build manifest's per module-version entries (current + carried-over
        /// skipped ones), for the incremental build's manifest.
        var manifestModules: [String: DocCBuildManifest.Entry] = [:]
        /// Modules skipped this build (unchanged), for logging.
        var skipped: [String] = []
        /// Every indexable page (default-version symbols + the catalog), for the
        /// sitemap. Sourced from the assembled search index so it stays complete
        /// across incremental builds (skipped modules keep their persisted
        /// fragments).
        var indexablePages: [IndexablePage] = []
    }

    /// A sitemap-bound page: a site-relative location (no leading slash) and an
    /// optional `<lastmod>` (a module's archive build date; `nil` for the catalog).
    struct IndexablePage: Sendable {
        var location: String
        var lastmod: String?
    }

    /// The archive location convention: `<archives>/<versionID>/<Module>.doccarchive`.
    /// Stage-A CI builds a package at a ref and writes its modules' archives here.
    static func archiveURL(module: Module, version: PackageVersion, in archivesBase: URL) -> URL {
        archivesBase
            .appendingPathComponent(version.id, isDirectory: true)
            .appendingPathComponent("\(module.name).doccarchive", isDirectory: true)
    }

    /// - Parameters:
    ///   - incremental: reuse output for modules whose archives are unchanged.
    ///   - previous: the previous build's manifest module entries (for skip checks).
    func run(
        renderer: TemplateRenderer,
        writer: OutputWriter,
        incremental: Bool = false,
        previous: [String: DocCBuildManifest.Entry] = [:]
    ) async throws -> Result {
        let registry = DocCModuleRegistry(site: docc, basePath: basePath)
        let switcher = DocCModuleSwitcher(docc: docc, basePath: basePath)
        // Resolve the archives directory *within* the content directory (append
        // components rather than URL(relativeTo:), which drops a base's last
        // component when it has no trailing slash).
        var archivesBase = contentDirectory
        for component in docc.archivesDirectory.split(separator: "/") {
            archivesBase.appendPathComponent(String(component), isDirectory: true)
        }
        let loader = DocCArchiveLoader()
        let language = site.defaultLanguage
        var result = Result()
        // Per-module sitemap <lastmod> (its default archive's build date), keyed by
        // the module's lowercased name — the same key as its search fragment file.
        // Recorded for skipped modules too, so the regenerated sitemap stays dated.
        var moduleLastmod: [String: String] = [:]

        let fileManager = FileManager.default
        for package in docc.packages {
            // Module switcher lists all modules; identical across a module's pages.
            for module in package.modules {
                // Per-version archive state (cheap fingerprints; no decode yet).
                struct VersionState { let version: PackageVersion; let archiveURL: URL; let key: String; let fingerprint: String; let relativeDir: String }
                var states: [VersionState] = []
                for version in package.versions {
                    let archiveURL = Self.archiveURL(module: module, version: version, in: archivesBase)
                    guard fileManager.fileExists(atPath: archiveURL.path) else {
                        result.warnings.append("missing archive for \(module.name)@\(version.id) at \(archiveURL.path)")
                        continue
                    }
                    let urls = DocCURLs(moduleName: module.name, version: version, basePath: basePath)
                    states.append(VersionState(
                        version: version, archiveURL: archiveURL,
                        key: "\(module.name)@\(version.id)",
                        fingerprint: DocCFingerprint.archive(archiveURL),
                        relativeDir: urls.relativeModuleDirectory
                    ))
                }
                guard !states.isEmpty else { continue }

                // Record the module's sitemap <lastmod> from its default archive's
                // newest mtime (before the skip check, so skipped modules keep a date).
                if let defaultState = states.first(where: { $0.version.isDefault }),
                   let mtime = DocCFingerprint.newestMTime(defaultState.archiveURL) {
                    moduleLastmod[module.name.lowercased()] = BlogDateFormatting.iso(mtime)
                }

                // Incremental skip: every version unchanged AND its output present.
                let canSkip = incremental && states.allSatisfy { state in
                    previous[state.key]?.fingerprint == state.fingerprint
                        && fileManager.fileExists(atPath: outputDirectory.appendingPathComponent(state.relativeDir).path)
                }
                if canSkip {
                    for state in states { result.manifestModules[state.key] = previous[state.key] }
                    result.skipped.append(module.name)
                    continue
                }

                // (Re)rendering this module: clear stale output for its versions
                // (a full build already reset the output).
                if incremental {
                    for state in states {
                        try? fileManager.removeItem(at: outputDirectory.appendingPathComponent(state.relativeDir))
                    }
                }

                // Load every version's archive (the version switcher needs each
                // version's page paths to resolve/fall back).
                var archivesByVersion: [String: DocCArchive] = [:]
                for state in states {
                    let diagnostics = DocCDiagnostics()
                    let archive = try loader.load(archiveURL: state.archiveURL, diagnostics: diagnostics)
                    archivesByVersion[state.version.id] = archive
                    result.manifestModules[state.key] = DocCBuildManifest.Entry(fingerprint: state.fingerprint, outputDir: state.relativeDir)
                    for issue in archive.loadIssues { result.warnings.append("[\(state.key)] \(issue)") }
                    for unknown in diagnostics.summary { result.warnings.append("[\(state.key)] unhandled \(unknown)") }
                }
                guard !archivesByVersion.isEmpty else { continue }

                let pathsByVersion = archivesByVersion.mapValues { Set($0.pages.map(\.path)) }
                let versionSwitcher = DocCVersionSwitcher(package: package, moduleName: module.name,
                                                          basePath: basePath, pathsByVersion: pathsByVersion)
                let moduleSwitcherHTML = switcher.renderHTML(currentModule: module.name)

                // Search: collect this module's default-version symbols only.
                var moduleSearch = SearchIndexBuilder()

                for version in package.versions {
                    guard let archive = archivesByVersion[version.id] else { continue }
                    let urls = DocCURLs(moduleName: module.name, version: version, basePath: basePath)
                    let contentRenderer = DocCRenderer(pathMapper: registry.linkMapper(current: urls, currentPackageRepo: package.repo))
                    let navigationBuilder = DocCNavigationBuilder(urls: urls)
                    // The sidebar tree is identical for every page of this module,
                    // so render it once; the current page is highlighted in the
                    // browser (docc-nav.js).
                    let sidebar = navigationBuilder.renderHTML(navigationBuilder.build(archive.index))

                    for page in archive.pages {
                        let rendered = contentRenderer.render(page.node)
                        let versionSwitcherHTML = versionSwitcher.renderHTML(currentVersion: version, currentPath: page.path)
                        let html = try await renderPage(page: page, rendered: rendered, urls: urls,
                                                        moduleTitle: module.displayTitle,
                                                        sidebarHTML: sidebar,
                                                        moduleSwitcherHTML: moduleSwitcherHTML,
                                                        versionSwitcherHTML: versionSwitcherHTML,
                                                        isDefaultVersion: version.isDefault,
                                                        language: language, renderer: renderer)
                        try writer.write(html, to: urls.outputFile(forDocCPath: page.path, in: outputDirectory))
                        // Only default versions are indexed (search.js prepends "/",
                        // so store the location without a leading slash).
                        if version.isDefault {
                            moduleSearch.add(
                                location: String(urls.url(forDocCPath: page.path).drop(while: { $0 == "/" })),
                                title: rendered.title,
                                html: rendered.abstractText ?? ""
                            )
                        }
                    }

                    // Copy the archive's referenced assets into the module dir.
                    try AssetCopier(outputDirectory: outputDirectory)
                        .copyDocCAssets(from: archive.archiveURL, into: urls.moduleDirectory(in: outputDirectory))
                }

                // Persist this module's search fragment (reused on incremental
                // builds when the module is skipped).
                try writer.write(try moduleSearch.jsonData(), to: Self.searchFragmentURL(module: module.name, in: outputDirectory))
            }
        }

        // Remove search fragments for modules no longer present.
        if incremental {
            for (key, _) in previous where result.manifestModules[key] == nil {
                let moduleName = String(key.prefix(while: { $0 != "@" }))
                if result.manifestModules.keys.contains(where: { $0.hasPrefix("\(moduleName)@") }) { continue }
                try? fileManager.removeItem(at: Self.searchFragmentURL(module: moduleName, in: outputDirectory))
            }
        }

        // Incremental cleanup: remove output for module-versions that existed in
        // the previous build but are no longer in the config.
        if incremental {
            for (key, entry) in previous where result.manifestModules[key] == nil {
                try? fileManager.removeItem(at: outputDirectory.appendingPathComponent(entry.outputDir))
            }
        }

        // The catalog landing page (site root): links to every module.
        let catalogHTML = try await renderCatalog(language: language,
                                                  moduleSwitcherHTML: switcher.renderHTML(currentModule: nil),
                                                  renderer: renderer)
        try writer.write(catalogHTML, to: outputDirectory.appendingPathComponent("index.html"))

        // Sitewide search index (default-version symbols from every module) and
        // the AI/agent module index. The assembled index doubles as the sitemap's
        // page set — same "indexable pages" definition, complete under incremental.
        result.indexablePages = try assembleSearchIndex(writer: writer, moduleLastmod: moduleLastmod)
        if site.llmsText { try writeLLMSIndex(writer: writer) }

        return result
    }

    // MARK: Search + LLMs

    /// A module's search fragment: `_kiln/search/<module>.json`.
    static func searchFragmentURL(module: String, in outputDirectory: URL) -> URL {
        outputDirectory
            .appendingPathComponent("_kiln/search", isDirectory: true)
            .appendingPathComponent("\(module.lowercased()).json")
    }

    /// Assemble the sitewide search index from every module's fragment (plus the
    /// catalog), so search works from any page. Fragment-based so an incremental
    /// build that skips modules still ships a complete index.
    ///
    /// Returns every indexed page (site-relative location + a `<lastmod>` from the
    /// owning module's `moduleLastmod` entry) for the sitemap — the same "indexable
    /// pages" set, kept in sync for free. The catalog has no lastmod.
    private func assembleSearchIndex(writer: OutputWriter, moduleLastmod: [String: String]) throws -> [IndexablePage] {
        var builder = SearchIndexBuilder()
        var pages: [IndexablePage] = []
        // The catalog / home page.
        builder.add(location: "", title: site.name, html: site.description ?? "")
        pages.append(IndexablePage(location: "", lastmod: nil))

        let fragmentsDir = outputDirectory.appendingPathComponent("_kiln/search", isDirectory: true)
        let decoder = JSONDecoder()
        if let enumerator = FileManager.default.enumerator(at: fragmentsDir, includingPropertiesForKeys: nil) {
            for case let file as URL in enumerator where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let index = try? decoder.decode(SearchIndex.self, from: data) else { continue }
                // The fragment filename is the module's lowercased name (its lastmod key).
                let lastmod = moduleLastmod[file.deletingPathExtension().lastPathComponent]
                for doc in index.docs {
                    builder.add(document: doc)
                    pages.append(IndexablePage(location: doc.location, lastmod: lastmod))
                }
            }
        }
        try writer.write(try builder.jsonData(),
                         to: outputDirectory.appendingPathComponent("search/search_index.json"))
        return pages
    }

    /// Write a compact `llms.txt` listing every module (default versions), grouped
    /// like the catalog — the AI/agent index for the API. No full corpus.
    private func writeLLMSIndex(writer: OutputWriter) throws {
        let sections = DocCCatalogBuilder(docc: docc, basePath: basePath).groups().map { group in
            LLMSText.Section(
                title: group.title,
                links: group.entries.map { LLMSText.Link(title: $0.title, url: absoluteURL($0.url)) }
            )
        }
        let llms = LLMSText.index(title: site.name, summary: site.description, sections: sections)
        try writer.write(llms, to: outputDirectory.appendingPathComponent("llms.txt"))
        // No full corpus for API reference (5k+ symbols) — drop any placeholder
        // the markdown phase wrote.
        try? FileManager.default.removeItem(at: outputDirectory.appendingPathComponent("llms-full.txt"))
    }

    // MARK: Catalog

    private func renderCatalog(language: Language, moduleSwitcherHTML: String, renderer: TemplateRenderer) async throws -> String {
        let catalogURL = basePath.isEmpty ? "/" : basePath + "/"

        var body = "<header class=\"docc-catalog-header\">\n<h1>\(HTMLEscaping.text(site.name))</h1>\n"
        if let description = site.description, !description.isEmpty {
            body += "<p class=\"docc-catalog-lead\">\(HTMLEscaping.text(description))</p>\n"
        }
        body += "</header>\n"
        body += DocCCatalogBuilder(docc: docc, basePath: basePath).renderHTML()

        let socialImage = socialImageURL(for: language)
        let context = RenderContext(
            site: site,
            language: language,
            // DocC sites are single-language; the version's default language is
            // the same one, so `#localise` fallbacks resolve against it.
            defaultLanguage: language,
            localisation: language.localisation,
            alternates: [],
            searchEnabled: true,
            searchIndexURL: basePath + "/search/search_index.json",
            markdownURL: nil,
            baseURL: "./",
            basePath: basePath,
            pageTitle: site.name,
            contentHTML: body,
            tableOfContents: [],
            // Keep the sidebar (with the expanded module switcher) as a module
            // navigator on the landing; there's no on-page TOC to show.
            frontMatter: FrontMatter(values: ["toc": "false"]),
            pageURL: catalogURL,
            canonicalURL: absoluteURL(catalogURL),
            pageDescription: site.description,
            socialImageURL: socialImage,
            editURL: nil,
            sourcePath: "",
            isHome: true,
            isFallback: false,
            navigation: PageNavigation(nodes: [], previous: nil, next: nil),
            doccModuleSwitcherHTML: moduleSwitcherHTML.isEmpty ? nil : moduleSwitcherHTML,
            version: VersionContext()
        )
        return try await renderer.render("page", context: context.leafData)
    }

    // MARK: Page rendering

    private func renderPage(
        page: DocCPage,
        rendered: RenderedDocC,
        urls: DocCURLs,
        moduleTitle: String,
        sidebarHTML: String,
        moduleSwitcherHTML: String,
        versionSwitcherHTML: String,
        isDefaultVersion: Bool,
        language: Language,
        renderer: TemplateRenderer
    ) async throws -> String {
        let pageURL = urls.url(forDocCPath: page.path)
        let canonical = absoluteURL(pageURL)

        // The `<title>`: a symbol page appends its module so it reads
        // "Queue · Queues · <site>" (matching the theme's " · <site>" suffix) and
        // disambiguates same-named symbols across modules. The module landing page
        // (empty DocC suffix) keeps just its own title to avoid "Queues · Queues".
        let isModuleLanding = urls.suffix(forDocCPath: page.path).isEmpty
        let pageTitle = isModuleLanding ? rendered.title : "\(rendered.title) · \(moduleTitle)"

        // page.leaf emits page.content verbatim, so the DocC body carries its own
        // header (role eyebrow + <h1>) — the render node deliberately omits it.
        var body = "<header class=\"docc-header\">\n"
        if let role = rendered.roleHeading, !role.isEmpty {
            body += "<p class=\"docc-eyebrow\">\(HTMLEscaping.text(role))</p>\n"
        }
        // A symbol page's title is a code identifier (type/method name), so tag it
        // for the code font. The module landing (its own symbolKind is "module")
        // and articles (no symbolKind) keep the prose heading font.
        let isSymbolTitle = !isModuleLanding && rendered.symbolKind != nil
        let titleClass = isSymbolTitle ? " class=\"docc-symbol-title\"" : ""
        body += "<h1\(titleClass)>\(HTMLEscaping.text(rendered.title))</h1>\n</header>\n"
        body += rendered.contentHTML

        // Non-default package versions are noindex (duplicate/older content).
        var versionContext = VersionContext()
        versionContext.noindex = !isDefaultVersion

        // Breadcrumb: the resolved ancestry (module → … → parent) plus the current
        // page as a trailing, unlinked crumb. Only symbol pages have ancestors; a
        // module landing gets none (Home → Module alone isn't worth a trail).
        let breadcrumb = rendered.breadcrumb.isEmpty
            ? nil
            : rendered.breadcrumb + [BreadcrumbItem(name: rendered.title, url: nil)]

        let context = RenderContext(
            site: site,
            language: language,
            // DocC sites are single-language; the version's default language is
            // the same one, so `#localise` fallbacks resolve against it.
            defaultLanguage: language,
            localisation: language.localisation,
            alternates: [],
            searchEnabled: true,
            searchIndexURL: basePath + "/search/search_index.json",
            markdownURL: nil,
            baseURL: urls.baseURL(forDocCPath: page.path),
            basePath: basePath,
            pageTitle: pageTitle,
            contentHTML: body,
            tableOfContents: rendered.tableOfContents,
            frontMatter: .empty,
            pageURL: pageURL,
            canonicalURL: canonical,
            pageDescription: rendered.abstractText ?? language.description ?? site.description,
            socialImageURL: socialImageURL(for: language),
            editURL: nil,
            sourcePath: "",
            isHome: false,
            isFallback: false,
            navigation: PageNavigation(nodes: [], previous: nil, next: nil),
            doccSidebarHTML: sidebarHTML.isEmpty ? nil : sidebarHTML,
            doccModuleSwitcherHTML: moduleSwitcherHTML.isEmpty ? nil : moduleSwitcherHTML,
            doccVersionSwitcherHTML: versionSwitcherHTML.isEmpty ? nil : versionSwitcherHTML,
            version: versionContext,
            breadcrumbOverride: breadcrumb
        )
        return try await renderer.render("page", context: context.leafData)
    }

    /// Join the site origin (`site.url`) with a site-relative path.
    private func absoluteURL(_ siteRelative: String) -> String {
        let base = site.url.hasSuffix("/") ? String(site.url.dropLast()) : site.url
        return base + siteRelative
    }

    /// The absolute social/OpenGraph image URL for a language (its own image, else
    /// the site default), for `<meta property="og:image">`.
    private func socialImageURL(for language: Language) -> String? {
        (language.image ?? site.image).map { absoluteURL(basePath + "/" + $0.drop(while: { $0 == "/" })) }
    }
}
