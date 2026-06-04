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
    let linkChecking: LinkChecking

    public init(site: KilnSite, contentDirectory: URL, outputDirectory: URL, linkChecking: LinkChecking = .warn) {
        self.site = site
        self.contentDirectory = contentDirectory
        self.outputDirectory = outputDirectory
        self.linkChecking = linkChecking
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
        let linkData = LinkData()
        var defaultNav: ResolvedNavigation?

        for language in site.buildableLanguages {
            let resolvedNav = navigationBuilder.build(site.navigation, for: language)
            if language.isDefault { defaultNav = resolvedNav }
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
                    searchIndex: &searchIndex,
                    linkData: linkData
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

        // Sitemap + robots.txt.
        try writer.write(sitemap(for: sitemapEntries), to: outputDirectory.appendingPathComponent("sitemap.xml"))
        try writer.write(robotsTxt(), to: outputDirectory.appendingPathComponent("robots.txt"))

        // AI/agent-friendly index files (default language).
        if site.llmsText, let defaultNav {
            try writeLLMSFiles(nav: defaultNav, store: store, defaultLocale: defaultLocale, writer: writer)
        }

        // Validate internal links last, once every page and its headings are known.
        if linkChecking != .off {
            try checkLinks(linkData, defaultLocale: defaultLocale)
        }
    }

    // MARK: Link checking

    /// Validate collected internal links, report problems, and (in `.error`
    /// mode) throw if any were found.
    private func checkLinks(_ linkData: LinkData, defaultLocale: String) throws {
        let checker = LinkChecker(
            builtPages: linkData.builtPages,
            slugs: linkData.slugs,
            defaultLocale: defaultLocale,
            knownLocales: Set(site.languages.map(\.locale)),
            assetExists: { [contentDirectory] relativePath in
                FileManager.default.fileExists(atPath: contentDirectory.appendingPathComponent(relativePath).path)
            }
        )

        // Collect, de-duplicating issues that repeat across locales (a fallback
        // page reproduces the default-language file's links in every locale).
        var issues: [LinkIssue] = []
        var seen: Set<String> = []
        for record in linkData.records {
            for issue in checker.issues(forPage: record.logicalPath, locale: record.locale,
                                        sourcePath: record.sourcePath, links: record.links, images: record.images) {
                let key = "\(issue.sourcePath)\t\(issue.link)\t\(issue.message)"
                if seen.insert(key).inserted { issues.append(issue) }
            }
        }

        guard !issues.isEmpty else { return }

        var report = "[kiln] link check: \(issues.count) broken link(s):\n"
        for issue in issues {
            report += "  \(issue.sourcePath): \(issue.message)\n"
        }
        FileHandle.standardError.write(Data(report.utf8))

        if linkChecking == .error {
            throw BrokenLinksError(issues: issues)
        }
    }

    // MARK: AI / agent-friendly output

    /// Write `llms.txt` (a structured index) and `llms-full.txt` (the full
    /// corpus) for the default language.
    private func writeLLMSFiles(nav: ResolvedNavigation, store: ContentStore, defaultLocale: String, writer: OutputWriter) throws {
        // llms.txt — top-level pages first, then a section per nav group.
        var rootLinks: [LLMSText.Link] = []
        var sections: [LLMSText.Section] = []
        for node in nav.nodes {
            switch node.kind {
            case .section:
                sections.append(LLMSText.Section(title: node.title, links: llmsLinks(node.items)))
            case .page, .link:
                rootLinks.append(contentsOf: llmsLinks([node]))
            }
        }
        var allSections: [LLMSText.Section] = []
        if !rootLinks.isEmpty { allSections.append(LLMSText.Section(title: nil, links: rootLinks)) }
        allSections.append(contentsOf: sections)
        let index = LLMSText.index(title: site.name, summary: site.description, sections: allSections)
        try writer.write(index, to: outputDirectory.appendingPathComponent("llms.txt"))

        // llms-full.txt — every default-language page's markdown, in nav order.
        var pages: [LLMSText.Page] = []
        for ref in nav.orderedPages {
            guard let page = store.page(forLogicalPath: ref.logicalPath, locale: defaultLocale, defaultLocale: defaultLocale) else { continue }
            pages.append(LLMSText.Page(url: absoluteURL(forLocation: String(ref.url.drop(while: { $0 == "/" }))), body: page.body))
        }
        let full = LLMSText.full(title: site.name, summary: site.description, pages: pages)
        try writer.write(full, to: outputDirectory.appendingPathComponent("llms-full.txt"))
    }

    /// Flatten nav nodes into `llms.txt` links, pointing at each page's raw markdown.
    private func llmsLinks(_ nodes: [NavNode]) -> [LLMSText.Link] {
        var links: [LLMSText.Link] = []
        for node in nodes {
            switch node.kind {
            case .page:
                if let url = node.url {
                    let location = String(url.drop(while: { $0 == "/" })) + "index.md"
                    links.append(LLMSText.Link(title: node.title, url: absoluteURL(forLocation: location)))
                }
            case .link:
                if let url = node.url { links.append(LLMSText.Link(title: node.title, url: url)) }
            case .section:
                links.append(contentsOf: llmsLinks(node.items))
            }
        }
        return links
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
        searchIndex: inout SearchIndexBuilder,
        linkData: LinkData
    ) async throws -> String {
        guard let page = store.page(forLogicalPath: logicalPath, locale: language.locale, defaultLocale: defaultLocale) else {
            throw ContentError.missingPage(logicalPath: logicalPath)
        }

        let linkResolver = LinkResolver(currentLogicalPath: logicalPath, locale: language.locale, urls: urls,
                                        knownLocales: Set(site.languages.map(\.locale)))
        let rendered = markdown.render(page.body, linkResolver: linkResolver)
        let title = page.frontMatter.title ?? rendered.firstHeading ?? navTitle
        let isFallback = !language.isDefault && !store.hasTranslation(forLogicalPath: logicalPath, locale: language.locale)
        let pageNavigation = navigationBuilder.contextualise(resolvedNav, currentLogicalPath: logicalPath)
        let urlPath = urls.urlPath(forLogicalPath: logicalPath, locale: language.locale)
        let sourceRelative = ContentLoader.relativePath(of: page.sourceURL, from: contentDirectory)
        let imagePath = page.frontMatter.image ?? site.image

        if linkChecking != .off {
            linkData.add(logicalPath: logicalPath, locale: language.locale, sourcePath: sourceRelative, rendered: rendered)
        }

        let context = RenderContext(
            site: site,
            language: language,
            localisation: language.localisation,
            alternates: alternates(forLogicalPath: logicalPath, current: language, urls: urls),
            searchEnabled: true,
            searchIndexURL: searchIndexURLPath(locale: language.locale, isDefault: language.isDefault),
            markdownURL: site.llmsText ? urlPath + "index.md" : nil,
            baseURL: urls.baseURL(forLogicalPath: logicalPath, locale: language.locale),
            pageTitle: title,
            contentHTML: rendered.html,
            tableOfContents: rendered.tableOfContents,
            frontMatter: page.frontMatter,
            pageURL: urlPath,
            canonicalURL: absoluteURL(forLocation: String(urlPath.drop(while: { $0 == "/" }))),
            pageDescription: page.frontMatter.description ?? language.description ?? site.description,
            socialImageURL: imagePath.map { absoluteURL(forPath: $0) },
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

        // Raw-markdown copy next to the HTML, for AI/agent consumption.
        if site.llmsText {
            try writer.write(page.body, to: outputFile.deletingLastPathComponent().appendingPathComponent("index.md"))
        }

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
            localisation: language.localisation,
            alternates: [],
            searchEnabled: true,
            searchIndexURL: searchIndexURLPath(locale: language.locale, isDefault: language.isDefault),
            markdownURL: nil,
            baseURL: rootBase,
            pageTitle: language.localisation.resolved.notFoundTitle,
            contentHTML: "",
            tableOfContents: [],
            frontMatter: .empty,
            pageURL: rootBase + "404.html",
            canonicalURL: absoluteURL(forLocation: "404.html"),
            pageDescription: language.description ?? site.description,
            socialImageURL: site.image.map { absoluteURL(forPath: $0) },
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

    /// Absolute URL for a content-relative asset path (e.g. `assets/social-card.png`),
    /// passed through unchanged if it's already an absolute URL.
    private func absoluteURL(forPath path: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        return absoluteURL(forLocation: path.drop(while: { $0 == "/" }).description)
    }

    private func robotsTxt() -> String {
        """
        User-agent: *
        Allow: /

        Sitemap: \(absoluteURL(forLocation: "sitemap.xml"))
        """
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
