#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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

    /// A page written by the phase (for later sitemap/search integration).
    struct WrittenPage: Sendable {
        var url: String
        var title: String
        var abstract: String?
        var moduleName: String
        var noindex: Bool
    }

    struct Result: Sendable {
        var pages: [WrittenPage] = []
        var warnings: [String] = []
    }

    /// The archive location convention: `<archives>/<versionID>/<Module>.doccarchive`.
    /// Stage-A CI builds a package at a ref and writes its modules' archives here.
    static func archiveURL(module: Module, version: PackageVersion, in archivesBase: URL) -> URL {
        archivesBase
            .appendingPathComponent(version.id, isDirectory: true)
            .appendingPathComponent("\(module.name).doccarchive", isDirectory: true)
    }

    func run(renderer: TemplateRenderer, writer: OutputWriter) async throws -> Result {
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

        for package in docc.packages {
            // Module switcher lists all modules; identical across a module's pages.
            for module in package.modules {
                // Load every version of this module up front, so the version
                // switcher can resolve a symbol's URL in each version (or fall
                // back to that version's landing).
                var archivesByVersion: [String: DocCArchive] = [:]
                for version in package.versions {
                    let archiveURL = Self.archiveURL(module: module, version: version, in: archivesBase)
                    guard FileManager.default.fileExists(atPath: archiveURL.path) else {
                        result.warnings.append("missing archive for \(module.name)@\(version.id) at \(archiveURL.path)")
                        continue
                    }
                    let diagnostics = DocCDiagnostics()
                    let archive = try loader.load(archiveURL: archiveURL, diagnostics: diagnostics)
                    archivesByVersion[version.id] = archive
                    let label = "\(module.name)@\(version.id)"
                    for issue in archive.loadIssues { result.warnings.append("[\(label)] \(issue)") }
                    for unknown in diagnostics.summary { result.warnings.append("[\(label)] unhandled \(unknown)") }
                }
                guard !archivesByVersion.isEmpty else { continue }

                let pathsByVersion = archivesByVersion.mapValues { Set($0.pages.map(\.path)) }
                let versionSwitcher = DocCVersionSwitcher(package: package, moduleName: module.name,
                                                          basePath: basePath, pathsByVersion: pathsByVersion)
                let moduleSwitcherHTML = switcher.renderHTML(currentModule: module.name)

                for version in package.versions {
                    guard let archive = archivesByVersion[version.id] else { continue }
                    let urls = DocCURLs(moduleName: module.name, version: version, basePath: basePath)
                    let contentRenderer = DocCRenderer(pathMapper: registry.linkMapper(current: urls, currentPackageRepo: package.repo))
                    let navigationBuilder = DocCNavigationBuilder(urls: urls)
                    let navigationTree = navigationBuilder.build(archive.index)

                    for page in archive.pages {
                        let rendered = contentRenderer.render(page.node)
                        let sidebar = navigationBuilder.renderHTML(navigationTree, currentPath: page.path)
                        let versionSwitcherHTML = versionSwitcher.renderHTML(currentVersion: version, currentPath: page.path)
                        let html = try await renderPage(page: page, rendered: rendered, urls: urls,
                                                        sidebarHTML: sidebar,
                                                        moduleSwitcherHTML: moduleSwitcherHTML,
                                                        versionSwitcherHTML: versionSwitcherHTML,
                                                        isDefaultVersion: version.isDefault,
                                                        language: language, renderer: renderer)
                        try writer.write(html, to: urls.outputFile(forDocCPath: page.path, in: outputDirectory))
                        result.pages.append(WrittenPage(
                            url: urls.url(forDocCPath: page.path),
                            title: rendered.title,
                            abstract: rendered.abstractText,
                            moduleName: module.name,
                            noindex: !version.isDefault
                        ))
                    }

                    // Copy the archive's referenced assets into the module dir.
                    try AssetCopier(outputDirectory: outputDirectory)
                        .copyDocCAssets(from: archive.archiveURL, into: urls.moduleDirectory(in: outputDirectory))
                }
            }
        }

        // The catalog landing page (site root): links to every module.
        let catalogURL = basePath.isEmpty ? "/" : basePath + "/"
        let catalogHTML = try await renderCatalog(language: language,
                                                  moduleSwitcherHTML: switcher.renderHTML(currentModule: nil),
                                                  renderer: renderer)
        try writer.write(catalogHTML, to: outputDirectory.appendingPathComponent("index.html"))
        result.pages.append(WrittenPage(url: catalogURL, title: site.name, abstract: site.description,
                                        moduleName: "", noindex: false))

        return result
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

        let socialImage = site.image.map { absoluteURL(basePath + "/" + $0.drop(while: { $0 == "/" })) }
        let context = RenderContext(
            site: site,
            language: language,
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
        sidebarHTML: String,
        moduleSwitcherHTML: String,
        versionSwitcherHTML: String,
        isDefaultVersion: Bool,
        language: Language,
        renderer: TemplateRenderer
    ) async throws -> String {
        let pageURL = urls.url(forDocCPath: page.path)
        let canonical = absoluteURL(pageURL)

        // page.leaf emits page.content verbatim, so the DocC body carries its own
        // header (role eyebrow + <h1>) — the render node deliberately omits it.
        var body = "<header class=\"docc-header\">\n"
        if let role = rendered.roleHeading, !role.isEmpty {
            body += "<p class=\"docc-eyebrow\">\(HTMLEscaping.text(role))</p>\n"
        }
        body += "<h1>\(HTMLEscaping.text(rendered.title))</h1>\n</header>\n"
        body += rendered.contentHTML

        // Non-default package versions are noindex (duplicate/older content).
        var versionContext = VersionContext()
        versionContext.noindex = !isDefaultVersion

        let context = RenderContext(
            site: site,
            language: language,
            localisation: language.localisation,
            alternates: [],
            searchEnabled: true,
            searchIndexURL: basePath + "/search/search_index.json",
            markdownURL: nil,
            baseURL: urls.baseURL(forDocCPath: page.path),
            basePath: basePath,
            pageTitle: rendered.title,
            contentHTML: body,
            tableOfContents: rendered.tableOfContents,
            frontMatter: .empty,
            pageURL: pageURL,
            canonicalURL: canonical,
            pageDescription: rendered.abstractText ?? language.description ?? site.description,
            socialImageURL: nil,
            editURL: nil,
            sourcePath: "",
            isHome: false,
            isFallback: false,
            navigation: PageNavigation(nodes: [], previous: nil, next: nil),
            doccSidebarHTML: sidebarHTML.isEmpty ? nil : sidebarHTML,
            doccModuleSwitcherHTML: moduleSwitcherHTML.isEmpty ? nil : moduleSwitcherHTML,
            doccVersionSwitcherHTML: versionSwitcherHTML.isEmpty ? nil : versionSwitcherHTML,
            version: versionContext
        )
        return try await renderer.render("page", context: context.leafData)
    }

    /// Join the site origin (`site.url`) with a site-relative path.
    private func absoluteURL(_ siteRelative: String) -> String {
        let base = site.url.hasSuffix("/") ? String(site.url.dropLast()) : site.url
        return base + siteRelative
    }
}
