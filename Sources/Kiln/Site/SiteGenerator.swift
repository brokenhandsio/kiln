public import Foundation

/// Errors thrown while resolving the theme.
public enum ThemeError: Error, CustomStringConvertible {
    case bundledThemeMissing
    case customThemeDirectoryNotFound(String)

    public var description: String {
        switch self {
        case .bundledThemeMissing:
            return "Kiln's bundled default theme could not be located in the package resources."
        case .customThemeDirectoryNotFound(let path):
            return "Custom theme directory not found: \(path)"
        }
    }
}

/// Orchestrates a full site build: load content, render every page for every
/// language (with fallback), emit search indexes and error pages, and copy
/// assets.
public struct SiteGenerator {
    let site: KilnSite
    let contentDirectory: URL
    let outputDirectory: URL

    public init(site: KilnSite, contentDirectory: URL, outputDirectory: URL) {
        self.site = site
        self.contentDirectory = contentDirectory
        self.outputDirectory = outputDirectory
    }

    public func build() async throws {
        try site.validate()

        let locales = Set(site.languages.map(\.locale))
        let defaultLocale = site.defaultLanguage.locale
        let store = try ContentLoader().load(contentDirectory: contentDirectory, locales: locales, defaultLocale: defaultLocale)

        let urls = SiteURLs(defaultLocale: defaultLocale)
        let navigationBuilder = NavigationBuilder(urls: urls)
        let markdown = MarkdownRenderer(options: site.markdown)

        let theme = try resolveTheme()
        let renderer = TemplateRenderer(templateDirectories: theme.templates)
        defer { renderer.shutdown() }

        let writer = OutputWriter(outputDirectory: outputDirectory)
        try writer.reset()

        var sitemapEntries: [String] = []

        for language in site.buildableLanguages {
            let resolvedNav = navigationBuilder.build(site.navigation, for: language)
            var searchIndex = SearchIndexBuilder()

            for pageRef in resolvedNav.orderedPages {
                let location = try await renderPage(
                    logicalPath: pageRef.logicalPath,
                    navTitle: pageRef.title,
                    language: language,
                    defaultLocale: defaultLocale,
                    store: store,
                    markdown: markdown,
                    urls: urls,
                    navigationBuilder: navigationBuilder,
                    resolvedNav: resolvedNav,
                    renderer: renderer,
                    writer: writer,
                    searchIndex: &searchIndex
                )
                sitemapEntries.append(absoluteURL(forLocation: location))
            }

            // Per-language search index.
            try writer.write(try searchIndex.jsonData(), to: searchIndexFile(locale: language.locale, isDefault: language.isDefault))

            // Per-language 404 page.
            let notFound = try await render404(
                language: language,
                urls: urls,
                navigationBuilder: navigationBuilder,
                resolvedNav: resolvedNav,
                renderer: renderer
            )
            try writer.write(notFound, to: notFoundFile(locale: language.locale, isDefault: language.isDefault))
        }

        // Assets: theme first (bundle then custom override), then project content.
        let assetCopier = AssetCopier(outputDirectory: outputDirectory)
        try assetCopier.copyThemeAssets(from: theme.assets)
        try assetCopier.copyContentAssets(from: contentDirectory)

        // Sitemap.
        try writer.write(sitemap(for: sitemapEntries), to: outputDirectory.appendingPathComponent("sitemap.xml"))
    }

    // MARK: Page rendering

    /// Render one page and return its site-relative location (used for search
    /// and the sitemap).
    private func renderPage(
        logicalPath: String,
        navTitle: String,
        language: Language,
        defaultLocale: String,
        store: ContentStore,
        markdown: MarkdownRenderer,
        urls: SiteURLs,
        navigationBuilder: NavigationBuilder,
        resolvedNav: ResolvedNavigation,
        renderer: TemplateRenderer,
        writer: OutputWriter,
        searchIndex: inout SearchIndexBuilder
    ) async throws -> String {
        guard let page = store.page(forLogicalPath: logicalPath, locale: language.locale, defaultLocale: defaultLocale) else {
            throw ContentError.missingPage(logicalPath: logicalPath)
        }

        let rendered = markdown.render(page.body)
        let title = page.frontMatter.title ?? rendered.firstHeading ?? navTitle
        let isFallback = !language.isDefault && !store.hasTranslation(forLogicalPath: logicalPath, locale: language.locale)
        let pageNavigation = navigationBuilder.contextualise(resolvedNav, currentLogicalPath: logicalPath)
        let urlPath = urls.urlPath(forLogicalPath: logicalPath, locale: language.locale)
        let sourceRelative = ContentLoader.relativePath(of: page.sourceURL, from: contentDirectory)

        let context = RenderContext(
            site: site,
            language: language,
            alternates: alternates(forLogicalPath: logicalPath, current: language, urls: urls),
            searchEnabled: true,
            searchIndexURL: searchIndexURLPath(locale: language.locale, isDefault: language.isDefault),
            baseURL: urls.baseURL(forLogicalPath: logicalPath, locale: language.locale),
            pageTitle: title,
            contentHTML: rendered.html,
            tableOfContents: rendered.tableOfContents,
            frontMatter: page.frontMatter,
            pageURL: urlPath,
            editURL: site.repository?.editURI.map { $0 + sourceRelative },
            sourcePath: sourceRelative,
            isHome: page.isHome,
            isFallback: isFallback,
            navigation: pageNavigation
        )

        let templateName = page.frontMatter.template ?? (page.isHome ? "home" : "page")
        let html = try await renderer.render(templateName, context: context.leafData)
        let outputFile = urls.outputFile(forLogicalPath: logicalPath, locale: language.locale, in: outputDirectory)
        try writer.write(html, to: outputFile)

        let location = String(urlPath.drop(while: { $0 == "/" }))
        searchIndex.add(location: location, title: title, html: rendered.html)
        return location
    }

    private func render404(
        language: Language,
        urls: SiteURLs,
        navigationBuilder: NavigationBuilder,
        resolvedNav: ResolvedNavigation,
        renderer: TemplateRenderer
    ) async throws -> String {
        // A 404 page can be served from any path, so reference assets/links from
        // the site root rather than a page-relative base.
        let rootBase = language.isDefault ? "/" : "/\(language.locale)/"
        let context = RenderContext(
            site: site,
            language: language,
            alternates: [],
            searchEnabled: true,
            searchIndexURL: searchIndexURLPath(locale: language.locale, isDefault: language.isDefault),
            baseURL: rootBase,
            pageTitle: "Page not found",
            contentHTML: "",
            tableOfContents: [],
            frontMatter: .empty,
            pageURL: rootBase + "404.html",
            editURL: nil,
            sourcePath: "",
            isHome: false,
            isFallback: false,
            navigation: navigationBuilder.contextualise(resolvedNav, currentLogicalPath: "")
        )
        return try await renderer.render("404", context: context.leafData)
    }

    // MARK: Helpers

    private func alternates(forLogicalPath logicalPath: String, current: Language, urls: SiteURLs) -> [LanguageAlternate] {
        site.buildableLanguages.map { language in
            LanguageAlternate(
                locale: language.locale,
                name: language.name,
                url: urls.urlPath(forLogicalPath: logicalPath, locale: language.locale),
                isCurrent: language.locale == current.locale
            )
        }
    }

    private func localeDirectory(locale: String, isDefault: Bool) -> URL {
        isDefault ? outputDirectory : outputDirectory.appendingPathComponent(locale, isDirectory: true)
    }

    private func searchIndexFile(locale: String, isDefault: Bool) -> URL {
        localeDirectory(locale: locale, isDefault: isDefault)
            .appendingPathComponent("search", isDirectory: true)
            .appendingPathComponent("search_index.json")
    }

    private func notFoundFile(locale: String, isDefault: Bool) -> URL {
        localeDirectory(locale: locale, isDefault: isDefault).appendingPathComponent("404.html")
    }

    /// Absolute, root-relative URL of a language's search index JSON.
    private func searchIndexURLPath(locale: String, isDefault: Bool) -> String {
        (isDefault ? "" : "/\(locale)") + "/search/search_index.json"
    }

    private func absoluteURL(forLocation location: String) -> String {
        let base = site.url.hasSuffix("/") ? String(site.url.dropLast()) : site.url
        return base + "/" + location
    }

    private func sitemap(for locations: [String]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
        for location in locations {
            xml += "  <url><loc>\(location)</loc></url>\n"
        }
        xml += "</urlset>\n"
        return xml
    }

    private func resolveTheme() throws -> (templates: [URL], assets: [URL]) {
        guard let bundledTheme = Bundle.module.url(forResource: "DefaultTheme", withExtension: nil) else {
            throw ThemeError.bundledThemeMissing
        }
        let bundledTemplates = bundledTheme.appendingPathComponent("templates", isDirectory: true)

        switch site.theme.source {
        case .default:
            return (templates: [bundledTemplates], assets: [bundledTheme])
        case .custom(let directory):
            let customURL = URL(fileURLWithPath: directory, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            guard FileManager.default.fileExists(atPath: customURL.path) else {
                throw ThemeError.customThemeDirectoryNotFound(customURL.path)
            }
            let customTemplates = customURL.appendingPathComponent("templates", isDirectory: true)
            // Custom templates take priority; custom assets override bundled.
            return (templates: [customTemplates, bundledTemplates], assets: [bundledTheme, customURL])
        }
    }
}
