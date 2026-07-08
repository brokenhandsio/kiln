public import Foundation
public import LeafKit

/// Errors thrown while resolving the theme.
public enum ThemeError: Error, CustomStringConvertible {
    case bundledThemeMissing
    case customThemeDirectoryNotFound(String)
    case sharedLayerDirectoryNotFound(String)

    public var description: String {
        switch self {
        case .bundledThemeMissing:
            return "Kiln's bundled default theme could not be located in the package resources."
        case .customThemeDirectoryNotFound(let path):
            return "Custom theme directory not found: \(path)"
        case .sharedLayerDirectoryNotFound(let path):
            return "Shared theme layer directory not found: \(path)"
        }
    }
}

/// Orchestrates a full site build: load content, render every page for every
/// language (with fallback) of every version, emit search indexes, error pages,
/// version manifest, and assets.
public struct SiteGenerator {
    let site: KilnSite
    let contentDirectory: URL
    let outputDirectory: URL
    let linkChecking: LinkChecking
    let incremental: Bool
    let leafTags: [String: any LeafTag]

    public init(
        site: KilnSite,
        contentDirectory: URL,
        outputDirectory: URL,
        linkChecking: LinkChecking = .warn,
        incremental: Bool = false,
        leafTags: [String: any LeafTag] = [:]
    ) {
        self.site = site
        self.contentDirectory = contentDirectory
        self.outputDirectory = outputDirectory
        self.linkChecking = linkChecking
        self.incremental = incremental
        self.leafTags = leafTags
    }

    /// The site's mount path, normalised (e.g. `"/docs"` or `""`).
    private var basePath: String { SiteURLs.normaliseBasePath(site.basePath) }

    /// The base path as a trailing-slash location prefix (e.g. `"docs/"` or `""`),
    /// for prepending to root-relative asset locations.
    private var basePathLocationPrefix: String { basePath.isEmpty ? "" : String(basePath.dropFirst()) + "/" }

    /// Per-version resolved data, prepared once before rendering.
    private struct VersionBuild {
        let version: DocVersion
        let contentURL: URL
        let store: ContentStore
        let urls: SiteURLs
        let navigationBuilder: NavigationBuilder
        let defaultLocale: String
        let locales: Set<String>
        /// Resolved navigation per locale.
        let navByLocale: [String: ResolvedNavigation]
    }

    public func build() async throws {
        try site.validate()

        let theme = try resolveTheme()
        let renderer = TemplateRenderer(templateDirectories: theme.templates, leafTags: leafTags)
        // `shutdown()` is async (it must not block — see TemplateRenderer), so we
        // can't use `defer`; await it on both the success and error paths instead.
        do {
            try await build(into: renderer, theme: theme)
        } catch {
            await renderer.shutdown()
            throw error
        }
        await renderer.shutdown()
    }

    /// The body of ``build()``, with the template renderer injected so its
    /// lifetime (and async shutdown) is managed by the caller.
    private func build(into renderer: TemplateRenderer, theme: (templates: [URL], assets: [URL])) async throws {
        let writer = OutputWriter(outputDirectory: outputDirectory)

        // Incremental DocC: when the render inputs (executable + templates) match
        // the previous build's manifest, reuse the output and skip re-rendering
        // modules whose archives are unchanged. Otherwise do a clean full build.
        let renderInputs = DocCFingerprint.renderInputs(templateDirectories: theme.templates)
        let previousManifest = incremental ? DocCBuildManifest.load(from: outputDirectory) : nil
        let doIncremental = incremental && site.docc != nil
            && previousManifest?.renderInputs == renderInputs
            && FileManager.default.fileExists(atPath: outputDirectory.path)
        if doIncremental {
            FileHandle.standardError.write(Data("[kiln] docc: incremental build (render inputs unchanged)\n".utf8))
        } else {
            try writer.reset()
        }

        let markdown = MarkdownRenderer(options: site.markdown)
        let isVersioned = site.isVersioned

        // The DocC archives directory (Kiln-managed input under the content dir),
        // excluded from content-asset copying so its raw JSON never reaches output.
        let doccArchivesDirectory: URL? = site.docc.map { docc in
            var url = contentDirectory
            for component in docc.archivesDirectory.split(separator: "/") {
                url.appendPathComponent(String(component), isDirectory: true)
            }
            return url
        }

        // Resolve every version's content/nav once, building the page registry
        // used for cross-version equivalence.
        var builds: [VersionBuild] = []
        for version in site.effectiveVersions {
            let contentURL = version.contentDirectory.isEmpty
                ? contentDirectory
                : URL(fileURLWithPath: version.contentDirectory, relativeTo: contentDirectory)
            let locales = Set(version.languages.map(\.locale))
            let defaultLocale = version.defaultLanguage.locale
            let store = try ContentLoader().load(contentDirectory: contentURL, locales: locales, defaultLocale: defaultLocale)
            let urls = SiteURLs(defaultLocale: defaultLocale, versionPrefix: version.urlPrefix, basePath: basePath)
            let navigationBuilder = NavigationBuilder(urls: urls)

            var navByLocale: [String: ResolvedNavigation] = [:]
            for language in version.buildableLanguages {
                navByLocale[language.locale] = navigationBuilder.build(version.navigation, for: language)
            }

            builds.append(VersionBuild(
                version: version, contentURL: contentURL, store: store, urls: urls,
                navigationBuilder: navigationBuilder, defaultLocale: defaultLocale,
                locales: locales, navByLocale: navByLocale
            ))
        }

        let defaultBuild = builds.first(where: { $0.version.isDefault }) ?? builds[0]
        var sitemapEntries: [SitemapEntry] = []

        for build in builds {
            let version = build.version
            let linkData = LinkData()

            for language in version.buildableLanguages {
                guard let resolvedNav = build.navByLocale[language.locale] else { continue }
                var searchIndex = SearchIndexBuilder()

                for pageRef in resolvedNav.orderedPages {
                    let location = try await renderPage(
                        logicalPath: pageRef.logicalPath,
                        navTitle: pageRef.title,
                        language: language,
                        build: build,
                        allBuilds: builds,
                        defaultBuild: defaultBuild,
                        isVersioned: isVersioned,
                        markdown: markdown,
                        resolvedNav: resolvedNav,
                        renderer: renderer,
                        writer: writer,
                        searchIndex: &searchIndex,
                        linkData: linkData
                    )
                    if version.isDefault {
                        let alts = alternates(forLogicalPath: pageRef.logicalPath, current: language,
                                              urls: build.urls, languages: version.buildableLanguages)
                        sitemapEntries.append(SitemapEntry(loc: absoluteURL(forLocation: location), alternates: alts))
                    }
                }

                // Per-(version, locale) search index.
                let searchFile = build.urls.directory(forLocale: language.locale, in: outputDirectory)
                    .appendingPathComponent("search", isDirectory: true)
                    .appendingPathComponent("search_index.json")
                try writer.write(try searchIndex.jsonData(), to: searchFile)

                // Per-(version, locale) 404 page.
                let notFound = try await render404(
                    language: language, build: build, allBuilds: builds,
                    defaultBuild: defaultBuild, isVersioned: isVersioned,
                    resolvedNav: resolvedNav, renderer: renderer
                )
                try writer.write(notFound, to: build.urls.directory(forLocale: language.locale, in: outputDirectory)
                    .appendingPathComponent("404.html"))
            }

            // Content assets: default version → root, others → /<id>/. The DocC
            // archives directory is Kiln-managed input, not a content asset, so
            // it's excluded from the copy (otherwise the raw archive JSON would
            // leak into the output).
            try AssetCopier(outputDirectory: outputDirectory)
                .copyContentAssets(from: build.contentURL, into: version.urlPrefix, excluding: doccArchivesDirectory.map { [$0] } ?? [])

            // AI/agent output (per version, per language).
            if site.llmsText {
                try writeLLMSFiles(build: build, writer: writer)
            }

            // Link checking is per version (a page may exist in one version only).
            if linkChecking != .off {
                try checkLinks(linkData, version: version, contentURL: build.contentURL,
                               defaultLocale: build.defaultLocale, knownLocales: build.locales)
            }
        }

        // Blog: an additive phase that renders post pages plus generated listing
        // pages (paginated index, per-tag pages) and an RSS feed. Its sitemap
        // entries join the rest before the sitemap is written below.
        if let blog = site.blog {
            sitemapEntries += try await renderBlog(blog, defaultBuild: defaultBuild, renderer: renderer, writer: writer, markdown: markdown)
        }

        // DocC: an additive phase that renders each package/version/module's
        // pre-built archive into themed pages (see DocCRenderPhase).
        if let docc = site.docc {
            let phase = DocCRenderPhase(
                site: site, docc: docc, contentDirectory: contentDirectory,
                outputDirectory: outputDirectory, basePath: basePath
            )
            let result = try await phase.run(
                renderer: renderer, writer: writer,
                incremental: doIncremental, previous: previousManifest?.modules ?? [:]
            )
            if !result.skipped.isEmpty {
                FileHandle.standardError.write(Data("[kiln] docc: reused \(result.skipped.count) unchanged module(s): \(result.skipped.sorted().joined(separator: ", "))\n".utf8))
            }
            if !result.warnings.isEmpty {
                var report = "[kiln] docc: \(result.warnings.count) warning(s):\n"
                for warning in result.warnings { report += "  \(warning)\n" }
                FileHandle.standardError.write(Data(report.utf8))
            }
            // Add the DocC pages to the sitemap. Sourced from the assembled search
            // index (default-version symbols + catalog) so it stays complete on
            // incremental builds where unchanged modules aren't re-rendered.
            // Locations are site-relative with the base path already applied;
            // <lastmod> is the owning module's archive build date.
            for page in result.indexablePages {
                sitemapEntries.append(SitemapEntry(loc: absoluteURL(forLocation: page.location),
                                                   alternates: [], lastmod: page.lastmod))
            }
            // Persist the manifest for the next incremental build.
            try DocCBuildManifest(renderInputs: renderInputs, modules: result.manifestModules).write(to: outputDirectory)
        }

        // Theme assets once (identical across versions; referenced root-absolutely).
        try AssetCopier(outputDirectory: outputDirectory).copyThemeAssets(from: theme.assets)

        // Root sitemap (default version only — existing sites are unaffected) + robots.
        try writer.write(sitemap(for: sitemapEntries), to: outputDirectory.appendingPathComponent("sitemap.xml"))
        try writer.write(robotsTxt(), to: outputDirectory.appendingPathComponent("robots.txt"))

        // Versions manifest (only when versioned).
        if isVersioned {
            try writer.write(versionsManifest(builds), to: outputDirectory.appendingPathComponent("versions.json"))
        }
    }

    // MARK: Link checking

    /// Validate collected internal links, report problems, and (in `.error`
    /// mode) throw if any were found.
    private func checkLinks(_ linkData: LinkData, version: DocVersion, contentURL: URL, defaultLocale: String, knownLocales: Set<String>) throws {
        let checker = LinkChecker(
            builtPages: linkData.builtPages,
            slugs: linkData.slugs,
            defaultLocale: defaultLocale,
            knownLocales: knownLocales,
            assetExists: { relativePath in
                FileManager.default.fileExists(atPath: contentURL.appendingPathComponent(relativePath).path)
            }
        )

        var issues: [LinkIssue] = []
        var seen: Set<String> = []
        for record in linkData.records {
            for issue in checker.issues(forPage: record.logicalPath, locale: record.locale,
                                        sourcePath: record.sourcePath, isFallback: record.isFallback,
                                        links: record.links, images: record.images) {
                let key = "\(issue.sourcePath)\t\(issue.link)\t\(issue.message)"
                if seen.insert(key).inserted { issues.append(issue) }
            }
        }

        guard !issues.isEmpty else { return }

        // Label the report with the version, so broken links are attributable in
        // a multi-version build (empty for an unversioned site).
        let versionLabel = version.id.isEmpty ? "" : " [\(version.id)]"
        var report = "[kiln] link check\(versionLabel): \(issues.count) broken link(s):\n"
        for issue in issues {
            report += "  \(versionLabel.isEmpty ? "" : "\(version.id)/")\(issue.sourcePath): \(issue.message)\n"
        }
        FileHandle.standardError.write(Data(report.utf8))

        if linkChecking == .error {
            throw BrokenLinksError(issues: issues)
        }
    }

    // MARK: AI / agent-friendly output

    /// Write `llms.txt` for every language of a version (the default language's at
    /// the version root, others under `/<locale>/`), plus a single `llms-full.txt`
    /// corpus for the default language.
    ///
    /// When a version has more than one language, each `llms.txt` gets a
    /// "Translations" section linking to the other languages' `llms.txt`. The
    /// llms.txt convention only standardises the root `/llms.txt`, so this is a
    /// best-effort discovery hook: a tool that reads the canonical index can
    /// follow the links to the localised indexes. Only the default-language full
    /// corpus is emitted, to avoid duplicating mostly-fallback content N times.
    private func writeLLMSFiles(build: VersionBuild, writer: OutputWriter) throws {
        let store = build.store
        let defaultLocale = build.defaultLocale
        let languages = build.version.buildableLanguages

        for language in languages {
            guard let nav = build.navByLocale[language.locale] else { continue }
            let localeRoot = build.urls.directory(forLocale: language.locale, in: outputDirectory)
            let title = language.siteName ?? site.name
            let summary = language.description ?? site.description

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

            // Best-effort translation discovery: link the other languages' indexes.
            let others = languages.filter { $0.locale != language.locale }
            if !others.isEmpty {
                let links = others.map { other in
                    LLMSText.Link(title: other.name, url: llmsURL(forLocale: other.locale, build: build))
                }
                allSections.append(LLMSText.Section(title: "Translations", links: links))
            }

            let index = LLMSText.index(title: title, summary: summary, sections: allSections)
            try writer.write(index, to: localeRoot.appendingPathComponent("llms.txt"))

            // Full corpus: default language only (avoids N× mostly-fallback duplication).
            if language.isDefault {
                var pages: [LLMSText.Page] = []
                for ref in nav.orderedPages {
                    guard let page = store.page(forLogicalPath: ref.logicalPath, locale: language.locale, defaultLocale: defaultLocale) else { continue }
                    pages.append(LLMSText.Page(url: absoluteURL(forLocation: String(ref.url.drop(while: { $0 == "/" }))), body: page.body))
                }
                let full = LLMSText.full(title: title, summary: summary, pages: pages)
                try writer.write(full, to: localeRoot.appendingPathComponent("llms-full.txt"))
            }
        }
    }

    /// Absolute URL of a language's `llms.txt` within this version.
    private func llmsURL(forLocale locale: String, build: VersionBuild) -> String {
        let root = build.urls.urlPath(forLogicalPath: "index.md", locale: locale)
        return absoluteURL(forLocation: String(root.drop(while: { $0 == "/" })) + "llms.txt")
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
        build: VersionBuild,
        allBuilds: [VersionBuild],
        defaultBuild: VersionBuild,
        isVersioned: Bool,
        markdown: MarkdownRenderer,
        resolvedNav: ResolvedNavigation,
        renderer: TemplateRenderer,
        writer: OutputWriter,
        searchIndex: inout SearchIndexBuilder,
        linkData: LinkData
    ) async throws -> String {
        let version = build.version
        let urls = build.urls
        let store = build.store
        let defaultLocale = build.defaultLocale

        guard let page = store.page(forLogicalPath: logicalPath, locale: language.locale, defaultLocale: defaultLocale) else {
            throw ContentError.missingPage(logicalPath: logicalPath)
        }

        let linkResolver = LinkResolver(currentLogicalPath: logicalPath, locale: language.locale, urls: urls,
                                        knownLocales: build.locales)
        let rendered = markdown.render(page.body, linkResolver: linkResolver)
        let title = page.frontMatter.title ?? rendered.firstHeading ?? navTitle
        let isFallback = !language.isDefault && !store.hasTranslation(forLogicalPath: logicalPath, locale: language.locale)
        let pageNavigation = build.navigationBuilder.contextualise(resolvedNav, currentLogicalPath: logicalPath)
        let urlPath = urls.urlPath(forLogicalPath: logicalPath, locale: language.locale)
        let sourceRelative = ContentLoader.relativePath(of: page.sourceURL, from: build.contentURL)
        let imagePath = page.frontMatter.image ?? language.image ?? site.image

        if linkChecking != .off {
            linkData.add(logicalPath: logicalPath, locale: language.locale, sourcePath: sourceRelative, isFallback: isFallback, rendered: rendered)
        }

        // Versioning. Each version page is self-canonical (non-default versions
        // are also `noindex`, so there's no duplicate-content concern), and the
        // version switcher links to each version's home page.
        let canonical = absoluteURL(forLocation: String(urlPath.drop(while: { $0 == "/" })))
        let versionContext = VersionContext(
            isVersioned: isVersioned,
            alternates: isVersioned ? versionAlternates(builds: allBuilds, currentVersionID: version.id, currentLocale: language.locale) : [],
            currentID: version.id,
            currentName: version.name,
            isPrerelease: version.isPrerelease,
            deprecated: version.deprecated,
            isLatest: version.isDefault,
            latestURL: (isVersioned && !version.isDefault) ? homeURL(in: defaultBuild, currentLocale: language.locale) : nil,
            basePath: version.isDefault ? "" : "/" + version.id,
            noindex: isVersioned && !version.isDefault
        )

        let context = RenderContext(
            site: site,
            language: language,
            defaultLanguage: version.defaultLanguage,
            localisation: language.localisation,
            alternates: alternates(forLogicalPath: logicalPath, current: language, urls: urls, languages: version.buildableLanguages),
            searchEnabled: true,
            searchIndexURL: urls.searchIndexURLPath(forLocale: language.locale),
            markdownURL: site.llmsText ? urlPath + "index.md" : nil,
            baseURL: urls.baseURL(forLogicalPath: logicalPath, locale: language.locale),
            basePath: basePath,
            pageTitle: title,
            contentHTML: rendered.html,
            tableOfContents: rendered.tableOfContents,
            frontMatter: page.frontMatter,
            pageURL: urlPath,
            canonicalURL: canonical,
            // Prefer the page's own first-paragraph excerpt over the generic
            // site/language description so each page gets a unique snippet — but
            // not on the home page, where the curated site description is the
            // intended meta description.
            pageDescription: page.frontMatter.description ?? (page.isHome ? nil : rendered.metaDescription) ?? language.description ?? site.description,
            socialImageURL: imagePath.map { absoluteURL(forPath: $0) },
            // "Edit this page" only on the default (latest) version — the
            // repository's editURI maps to the latest content directory.
            editURL: version.isDefault ? site.repository?.editURI.map { $0 + sourceRelative } : nil,
            sourcePath: sourceRelative,
            isHome: page.isHome,
            isFallback: isFallback,
            navigation: pageNavigation,
            version: versionContext
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

    // MARK: Blog

    /// Render the blog: a post page per markdown file, a paginated index, a tags
    /// landing page, per-tag paginated pages, and an RSS feed. Returns the blog's
    /// sitemap entries (the caller merges them into the site sitemap).
    ///
    /// A blog is single-language and unversioned (enforced in
    /// ``KilnSite/validate()``), so this uses the default build's `SiteURLs` with
    /// empty version/locale prefixes throughout.
    private func renderBlog(
        _ blog: Blog,
        defaultBuild build: VersionBuild,
        renderer: TemplateRenderer,
        writer: OutputWriter,
        markdown: MarkdownRenderer
    ) async throws -> [SitemapEntry] {
        let urls = build.urls
        let language = build.version.defaultLanguage
        let locale = build.defaultLocale
        let resolvedNav = build.navByLocale[locale] ?? build.navigationBuilder.build([], for: language)
        let emptyNav = build.navigationBuilder.contextualise(resolvedNav, currentLogicalPath: "")
        let fallbackImage = language.image ?? site.image
        let perPage = max(1, blog.postsPerPage)

        let collection = BlogLoader(
            contentDirectory: build.contentURL,
            blog: blog,
            markdown: markdown,
            urls: urls,
            defaultLocale: locale,
            knownLocales: build.locales
        ).load()

        var sitemapEntries: [SitemapEntry] = []
        var searchIndex = SearchIndexBuilder()

        /// Render and write one blog page; returns its sitemap entry.
        @discardableResult
        func emit(
            template: String,
            urlPath: String,
            outputFile: URL,
            depth: Int,
            title: String,
            description: String?,
            socialImage: String?,
            isHome: Bool,
            contentHTML: String = "",
            blogPost: LeafData? = nil,
            blogListing: LeafData? = nil,
            article: ArticleStructuredData? = nil,
            profile: ProfileStructuredData? = nil,
            breadcrumb: [BreadcrumbItem]? = nil,
            lastmod: String? = nil
        ) async throws -> SitemapEntry {
            let location = String(urlPath.drop(while: { $0 == "/" }))
            let context = RenderContext(
                site: site,
                language: language,
                defaultLanguage: build.version.defaultLanguage,
                localisation: language.localisation,
                alternates: [],
                searchEnabled: true,
                searchIndexURL: urls.searchIndexURLPath(forLocale: locale),
                markdownURL: nil,
                baseURL: relativeBaseURL(depth: depth),
                basePath: basePath,
                pageTitle: title,
                contentHTML: contentHTML,
                tableOfContents: [],
                // Blog pages own their full-width layout — hide the doc nav/TOC rails.
                frontMatter: FrontMatter(values: ["sidebar": "false", "toc": "false"]),
                pageURL: urlPath,
                canonicalURL: absoluteURL(forLocation: location),
                pageDescription: description,
                socialImageURL: socialImage.map { absoluteURL(forPath: $0) },
                editURL: nil,
                sourcePath: "",
                isHome: isHome,
                isFallback: false,
                navigation: emptyNav,
                version: VersionContext(),
                blogPost: blogPost,
                blogListing: blogListing,
                articleStructuredData: article,
                breadcrumbOverride: breadcrumb,
                profileStructuredData: profile
            )
            let html = try await renderer.render(template, context: context.leafData)
            try writer.write(html, to: outputFile)
            return SitemapEntry(loc: absoluteURL(forLocation: location), alternates: [], lastmod: lastmod)
        }

        // 1. Post pages.
        for post in collection.posts {
            let urlPath = urls.urlPath(forLogicalPath: post.logicalPath, locale: locale)
            let location = String(urlPath.drop(while: { $0 == "/" }))
            let socialImage = post.socialImage ?? fallbackImage
            let article = ArticleStructuredData(
                type: "BlogPosting",
                headline: post.title,
                url: absoluteURL(forLocation: location),
                datePublished: BlogDateFormatting.iso8601(post.date),
                dateModified: nil,
                authors: post.authors.map { author in
                    // Person.url → the on-site author page; sameAs → every external profile.
                    let pageURL = author.username.map {
                        self.absoluteURL(forLocation: String(urls.blogAuthorURLPath(slug: Slugger.normalise($0), page: 1).drop(while: { $0 == "/" })))
                    }
                    return ArticleAuthor(name: author.name, url: pageURL, sameAs: author.sameAs)
                },
                image: socialImage.map { absoluteURL(forPath: $0) },
                description: post.excerpt.isEmpty ? nil : post.excerpt,
                keywords: post.tags
            )
            let entry = try await emit(
                template: "blog-post",
                urlPath: urlPath,
                outputFile: urls.outputFile(forLogicalPath: post.logicalPath, locale: locale, in: outputDirectory),
                depth: 2,
                title: post.title,
                description: post.excerpt.isEmpty ? (language.description ?? site.description) : post.excerpt,
                socialImage: socialImage,
                isHome: false,
                contentHTML: post.contentHTML,
                blogPost: BlogLeafData.post(post, urls: urls, blog: blog),
                article: article,
                // Home (the blog index) › this post — for a BreadcrumbList.
                breadcrumb: [BreadcrumbItem(name: post.title, url: nil)],
                lastmod: BlogDateFormatting.iso(post.date)
            )
            sitemapEntries.append(entry)
            searchIndex.add(location: location, title: post.title, html: post.contentHTML)
        }

        // Listing pages are as fresh as their newest post (for sitemap <lastmod>).
        let newestLastmod = collection.posts.first.map { BlogDateFormatting.iso($0.date) }
        let indexTitle = blog.indexTitle ?? (language.siteName ?? site.name)
        let tagsTitle = blog.tagsTitle ?? "Tags"
        let authorsTitle = blog.authorsTitle ?? "Authors"

        // 2. Paginated index (`/`, `/2/`, …) over all posts.
        let indexPages = pageCount(collection.posts.count, perPage: perPage)
        for page in 1...indexPages {
            let listing = BlogLeafData.listing(
                heading: indexTitle,
                cards: slice(collection.posts, page: page, perPage: perPage),
                currentPage: page, totalPages: indexPages,
                urlForPage: { urls.blogIndexURLPath(page: $0) },
                tags: collection.tags, activeTagSlug: nil, isTagsPage: false,
                totalPostCount: collection.posts.count, urls: urls, blog: blog,
                previousLabel: language.localisation.resolved.previousPage,
                nextLabel: language.localisation.resolved.nextPage
            )
            sitemapEntries.append(try await emit(
                template: "blog-index",
                urlPath: urls.blogIndexURLPath(page: page),
                outputFile: urls.blogIndexOutputFile(page: page, in: outputDirectory),
                depth: page == 1 ? 0 : 1,
                title: page == 1 ? indexTitle : "Page \(page)",
                description: language.description ?? site.description,
                socialImage: fallbackImage,
                isHome: page == 1,
                blogListing: listing,
                lastmod: newestLastmod
            ))
        }

        // 3. Tag directory (`/tags/`): every tag with its post count, but no post
        // feed — the index already lists the posts, so paginating them here too
        // would just be duplicate content. Per-tag pages (below) hold the posts.
        let tagsIndex = BlogLeafData.tagsIndex(
            heading: tagsTitle, tags: collection.tags,
            totalPostCount: collection.posts.count, urls: urls
        )
        sitemapEntries.append(try await emit(
            template: "blog-tags-index",
            urlPath: urls.blogTagsURLPath(page: 1),
            outputFile: urls.blogTagsOutputFile(page: 1, in: outputDirectory),
            depth: 1,
            title: tagsTitle,
            description: language.description ?? site.description,
            socialImage: fallbackImage,
            isHome: false,
            blogListing: tagsIndex,
            lastmod: newestLastmod
        ))

        // 4. Per-tag paginated pages (`/tags/<slug>/`, `/tags/<slug>/2/`, …).
        for tag in collection.tags {
            let tagged = collection.posts(taggedSlug: tag.slug)
            let tagPages = pageCount(tagged.count, perPage: perPage)
            for page in 1...tagPages {
                let listing = BlogLeafData.listing(
                    heading: tagsTitle,
                    cards: slice(tagged, page: page, perPage: perPage),
                    currentPage: page, totalPages: tagPages,
                    urlForPage: { urls.blogTagURLPath(slug: tag.slug, page: $0) },
                    tags: collection.tags, activeTagSlug: tag.slug, isTagsPage: true,
                    totalPostCount: collection.posts.count, urls: urls, blog: blog,
                    previousLabel: language.localisation.resolved.previousPage,
                    nextLabel: language.localisation.resolved.nextPage
                )
                sitemapEntries.append(try await emit(
                    template: "blog-tags",
                    urlPath: urls.blogTagURLPath(slug: tag.slug, page: page),
                    outputFile: urls.blogTagOutputFile(slug: tag.slug, page: page, in: outputDirectory),
                    depth: page == 1 ? 2 : 3,
                    title: page == 1 ? tag.name : "\(tag.name) — Page \(page)",
                    description: "Posts tagged \(tag.name).",
                    socialImage: fallbackImage,
                    isHome: false,
                    blogListing: listing,
                    lastmod: tagged.first.map { BlogDateFormatting.iso($0.date) }
                ))
            }
        }

        // 5. Authors index (`/authors/`) + per-author paginated pages.
        if !blog.authors.isEmpty {
            sitemapEntries.append(try await emit(
                template: "blog-authors-index",
                urlPath: urls.blogAuthorsURLPath(),
                outputFile: urls.blogAuthorsOutputFile(in: outputDirectory),
                depth: 1,
                title: authorsTitle,
                description: language.description ?? site.description,
                socialImage: fallbackImage,
                isHome: false,
                blogListing: BlogLeafData.authorsIndex(heading: authorsTitle, authors: blog.authors, urls: urls),
                lastmod: newestLastmod
            ))

            for author in blog.authors {
                let slug = Slugger.normalise(author.username)
                let authored = collection.posts(byAuthorUsername: author.username)
                let authorPages = pageCount(authored.count, perPage: perPage)
                let authorPageURL = absoluteURL(forLocation: String(urls.blogAuthorURLPath(slug: slug, page: 1).drop(while: { $0 == "/" })))
                for page in 1...authorPages {
                    let listing = BlogLeafData.authorPage(
                        author: author,
                        cards: slice(authored, page: page, perPage: perPage),
                        currentPage: page, totalPages: authorPages,
                        urlForPage: { urls.blogAuthorURLPath(slug: slug, page: $0) },
                        urls: urls, blog: blog,
                        previousLabel: language.localisation.resolved.previousPage,
                        nextLabel: language.localisation.resolved.nextPage
                    )
                    // The first page is the canonical author profile (ProfilePage + Person).
                    let profile = page == 1 ? ProfileStructuredData(
                        name: author.name,
                        url: authorPageURL,
                        image: author.imageURL.map { absoluteURL(forPath: $0) },
                        description: author.description,
                        sameAs: author.socialLinks.map(\.url)
                    ) : nil
                    sitemapEntries.append(try await emit(
                        template: "blog-author",
                        urlPath: urls.blogAuthorURLPath(slug: slug, page: page),
                        outputFile: urls.blogAuthorOutputFile(slug: slug, page: page, in: outputDirectory),
                        depth: page == 1 ? 2 : 3,
                        title: page == 1 ? author.name : "\(author.name) — Page \(page)",
                        description: author.description ?? "Posts by \(author.name).",
                        // The default blog OG card (a square avatar would be cropped in a
                        // summary_large_image card). The author photo still drives the
                        // visible page avatar and the Person/ProfilePage JSON-LD image.
                        socialImage: fallbackImage,
                        isHome: false,
                        blogListing: listing,
                        profile: profile,
                        lastmod: authored.first.map { BlogDateFormatting.iso($0.date) }
                    ))
                }
            }
        }

        // 6. RSS feed (written at the output root, served at `basePath/feed.rss`).
        let homeLocation = String(urls.blogIndexURLPath(page: 1).drop(while: { $0 == "/" }))
        let rss = RSSFeed.render(
            title: blog.feedTitle ?? site.name,
            description: blog.feedDescription ?? site.description ?? site.name,
            siteURL: absoluteURL(forLocation: homeLocation),
            feedURL: absoluteURL(forLocation: basePathLocationPrefix + "feed.rss"),
            siteOrigin: site.url.hasSuffix("/") ? String(site.url.dropLast()) : site.url,
            language: locale,
            posts: collection.posts,
            postURL: { post in
                self.absoluteURL(forLocation: String(urls.urlPath(forLogicalPath: post.logicalPath, locale: locale).drop(while: { $0 == "/" })))
            }
        )
        try writer.write(rss, to: outputDirectory.appendingPathComponent("feed.rss"))

        // Blog search index — overwrites the (empty) one the doc phase wrote for
        // this single locale, so on a blog-only site the posts are the index.
        let searchFile = urls.directory(forLocale: locale, in: outputDirectory)
            .appendingPathComponent("search", isDirectory: true)
            .appendingPathComponent("search_index.json")
        try writer.write(try searchIndex.jsonData(), to: searchFile)

        return sitemapEntries
    }

    /// Number of listing pages for `count` items at `perPage` each (at least 1,
    /// so an empty blog still emits a single index page).
    private func pageCount(_ count: Int, perPage: Int) -> Int {
        max(1, (count + perPage - 1) / perPage)
    }

    /// The slice of items shown on a 1-based listing page.
    private func slice<T>(_ items: [T], page: Int, perPage: Int) -> [T] {
        let start = (page - 1) * perPage
        guard start < items.count else { return [] }
        return Array(items[start..<min(start + perPage, items.count)])
    }

    /// Relative path back to the site root for a page at the given directory
    /// depth (`./` at the root, `../` one level down, …).
    private func relativeBaseURL(depth: Int) -> String {
        depth == 0 ? "./" : String(repeating: "../", count: depth)
    }

    private func render404(
        language: Language,
        build: VersionBuild,
        allBuilds: [VersionBuild],
        defaultBuild: VersionBuild,
        isVersioned: Bool,
        resolvedNav: ResolvedNavigation,
        renderer: TemplateRenderer
    ) async throws -> String {
        let version = build.version
        let urls = build.urls
        // A 404 can be served from any path, so reference assets/links from the
        // version+locale root rather than a page-relative base.
        let rootBase = urls.urlPath(forLogicalPath: "index.md", locale: language.locale) // e.g. "/", "/de/", "/4.0/"
        let alternatesForNotFound = isVersioned
            ? versionAlternates(builds: allBuilds, currentVersionID: version.id, currentLocale: language.locale)
            : []
        let latestHome = homeURL(in: defaultBuild, currentLocale: language.locale)
        let versionContext = VersionContext(
            isVersioned: isVersioned,
            alternates: alternatesForNotFound,
            currentID: version.id,
            currentName: version.name,
            isPrerelease: version.isPrerelease,
            deprecated: version.deprecated,
            isLatest: version.isDefault,
            latestURL: (isVersioned && !version.isDefault) ? latestHome : nil,
            basePath: version.isDefault ? "" : "/" + version.id,
            noindex: isVersioned && !version.isDefault
        )

        let context = RenderContext(
            site: site,
            language: language,
            defaultLanguage: version.defaultLanguage,
            localisation: language.localisation,
            alternates: [],
            searchEnabled: true,
            searchIndexURL: urls.searchIndexURLPath(forLocale: language.locale),
            markdownURL: nil,
            baseURL: rootBase,
            basePath: basePath,
            pageTitle: language.localisation.resolved.notFoundTitle,
            contentHTML: "",
            tableOfContents: [],
            frontMatter: .empty,
            pageURL: rootBase + "404.html",
            canonicalURL: absoluteURL(forLocation: String(rootBase.drop(while: { $0 == "/" })) + "404.html"),
            pageDescription: language.description ?? site.description,
            socialImageURL: (language.image ?? site.image).map { absoluteURL(forPath: $0) },
            editURL: nil,
            sourcePath: "",
            isHome: false,
            isFallback: false,
            navigation: build.navigationBuilder.contextualise(resolvedNav, currentLogicalPath: ""),
            version: versionContext
        )
        return try await renderer.render("404", context: context.leafData)
    }

    // MARK: Versioning helpers

    /// The version switcher entries: each version's home page. Switching version
    /// always lands on that version's home (kept deliberately simple — versions
    /// can have entirely different structures).
    private func versionAlternates(builds: [VersionBuild], currentVersionID: String, currentLocale: String) -> [VersionAlternate] {
        builds.map { build in
            VersionAlternate(
                id: build.version.id,
                name: build.version.name,
                url: homeURL(in: build, currentLocale: currentLocale),
                isCurrent: build.version.id == currentVersionID,
                isPrerelease: build.version.isPrerelease,
                deprecated: build.version.deprecated
            )
        }
    }

    /// A version's home page URL, in the current locale if that version has it,
    /// otherwise the version's default locale.
    private func homeURL(in build: VersionBuild, currentLocale: String) -> String {
        let locale = build.locales.contains(currentLocale) ? currentLocale : build.defaultLocale
        return build.urls.urlPath(forLogicalPath: "index.md", locale: locale)
    }

    private struct VersionManifestEntry: Encodable {
        let id: String
        let name: String
        let path: String
        let isDefault: Bool
        let isPrerelease: Bool
        let deprecated: Bool
        let order: Int
        let locales: [String]
    }

    private func versionsManifest(_ builds: [VersionBuild]) -> String {
        let entries = builds.enumerated().map { index, build -> VersionManifestEntry in
            let v = build.version
            return VersionManifestEntry(
                id: v.id,
                name: v.name,
                path: v.isDefault ? "/" : "/\(v.id)/",
                isDefault: v.isDefault,
                isPrerelease: v.isPrerelease,
                deprecated: v.deprecated,
                order: index,
                locales: v.buildableLanguages.map(\.locale)
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entries) else { return "[]\n" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    // MARK: Helpers

    private func alternates(forLogicalPath logicalPath: String, current: Language, urls: SiteURLs, languages: [Language]) -> [LanguageAlternate] {
        languages.map { language in
            let path = urls.urlPath(forLogicalPath: logicalPath, locale: language.locale)
            return LanguageAlternate(
                locale: language.locale,
                name: language.name,
                // Relative for the switcher; absolute (fully-qualified, as Google
                // requires) for the `hreflang` links.
                url: path,
                absoluteURL: absoluteURL(forLocation: String(path.drop(while: { $0 == "/" }))),
                isCurrent: language.locale == current.locale,
                isDefault: language.isDefault
            )
        }
    }

    private func absoluteURL(forLocation location: String) -> String {
        let base = site.url.hasSuffix("/") ? String(site.url.dropLast()) : site.url
        return base + "/" + location
    }

    /// Absolute URL for a content-relative asset path (e.g. `assets/social-card.png`),
    /// passed through unchanged if it's already an absolute URL. Content assets are
    /// copied under the base path, so it's injected here (page locations already
    /// carry it via ``SiteURLs``).
    private func absoluteURL(forPath path: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        return absoluteURL(forLocation: basePathLocationPrefix + path.drop(while: { $0 == "/" }).description)
    }

    private func robotsTxt() -> String {
        """
        User-agent: *
        Allow: /

        Sitemap: \(absoluteURL(forLocation: basePathLocationPrefix + "sitemap.xml"))
        """
    }

    /// One sitemap `<url>`: its absolute location plus the localised alternates
    /// (one per buildable language) for emitting `xhtml:link` hreflang.
    private struct SitemapEntry {
        let loc: String
        let alternates: [LanguageAlternate]
        /// W3C date (`YYYY-MM-DD`) for `<lastmod>`, when known (e.g. a post's date).
        var lastmod: String? = nil
    }

    private func sitemap(for entries: [SitemapEntry]) -> String {
        // Only declare the xhtml namespace (and emit hreflang) when the site is
        // multilingual; single-language sitemaps stay plain `<loc>`-only.
        let multilingual = entries.contains { $0.alternates.count > 1 }
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\""
        if multilingual { xml += " xmlns:xhtml=\"http://www.w3.org/1999/xhtml\"" }
        xml += ">\n"
        for entry in entries {
            if entry.alternates.count > 1 {
                xml += "  <url>\n    <loc>\(entry.loc)</loc>\n"
                if let lastmod = entry.lastmod { xml += "    <lastmod>\(lastmod)</lastmod>\n" }
                for alt in entry.alternates {
                    xml += "    <xhtml:link rel=\"alternate\" hreflang=\"\(alt.locale)\" href=\"\(alt.absoluteURL)\"/>\n"
                    if alt.isDefault {
                        xml += "    <xhtml:link rel=\"alternate\" hreflang=\"x-default\" href=\"\(alt.absoluteURL)\"/>\n"
                    }
                }
                xml += "  </url>\n"
            } else if let lastmod = entry.lastmod {
                xml += "  <url><loc>\(entry.loc)</loc><lastmod>\(lastmod)</lastmod></url>\n"
            } else {
                xml += "  <url><loc>\(entry.loc)</loc></url>\n"
            }
        }
        xml += "</urlset>\n"
        return xml
    }

    private func resolveTheme() throws -> (templates: [URL], assets: [URL]) {
        guard let bundledTheme = Bundle.module.url(forResource: "DefaultTheme", withExtension: nil) else {
            throw ThemeError.bundledThemeMissing
        }
        let bundledTemplates = bundledTheme.appendingPathComponent("templates", isDirectory: true)

        // Shared layers are absolute directories (typically resource-bundle URLs
        // from a shared design package), so they are NOT resolved against cwd.
        let sharedLayers = site.theme.sharedLayers
        for layer in sharedLayers where !FileManager.default.fileExists(atPath: layer.path) {
            throw ThemeError.sharedLayerDirectoryNotFound(layer.path)
        }
        let sharedTemplates = sharedLayers.map { $0.appendingPathComponent("templates", isDirectory: true) }

        switch site.theme.source {
        case .default:
            // Templates: highest priority first. Assets: lowest priority first
            // (copyThemeAssets overwrites bundle-first → shared-last).
            return (
                templates: sharedTemplates + [bundledTemplates],
                assets: [bundledTheme] + sharedLayers
            )
        case .custom(let directory):
            let customURL = URL(fileURLWithPath: directory, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            guard FileManager.default.fileExists(atPath: customURL.path) else {
                throw ThemeError.customThemeDirectoryNotFound(customURL.path)
            }
            let customTemplates = customURL.appendingPathComponent("templates", isDirectory: true)
            // Custom templates take priority, then shared layers, then bundled.
            // Assets: bundled first, then shared, then custom (custom wins).
            return (
                templates: [customTemplates] + sharedTemplates + [bundledTemplates],
                assets: [bundledTheme] + sharedLayers + [customURL]
            )
        }
    }
}
