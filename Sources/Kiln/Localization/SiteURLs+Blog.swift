#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// URL and output-file helpers for the generated blog listing pages (the
/// paginated index, the tags landing, and per-tag pages) and the RSS feed.
///
/// A blog is single-language and unversioned, so these paths carry no version
/// or locale prefix — only ``SiteURLs/basePath`` (for site-relative URLs). The
/// on-disk paths, like the doc pages', never include the base path (it's a
/// serving prefix, not an output directory).
extension SiteURLs {
    /// Site-relative URL of the index page: `/` for page 1, `/2/`, `/3/`… after.
    public func blogIndexURLPath(page: Int) -> String {
        basePath + "/" + pageSegment(page)
    }

    /// On-disk file for the index page (`index.html`, or `N/index.html`).
    public func blogIndexOutputFile(page: Int, in outputDirectory: URL) -> URL {
        outputFile(forSegments: pageComponents(page), in: outputDirectory)
    }

    /// Site-relative URL of the tags landing page: `/tags/`, then `/tags/2/`…
    /// (the landing paginates over *all* posts alongside the tag list).
    public func blogTagsURLPath(page: Int = 1) -> String {
        basePath + "/tags/" + pageSegment(page)
    }

    /// On-disk file for the tags landing page (`tags/index.html`, or `…/N/index.html`).
    public func blogTagsOutputFile(page: Int, in outputDirectory: URL) -> URL {
        outputFile(forSegments: ["tags"] + pageComponents(page), in: outputDirectory)
    }

    /// Site-relative URL of a per-tag page: `/tags/<slug>/`, then `/tags/<slug>/2/`…
    public func blogTagURLPath(slug: String, page: Int) -> String {
        basePath + "/tags/" + slug + "/" + pageSegment(page)
    }

    /// On-disk file for a per-tag page (`tags/<slug>/index.html`, or `…/N/index.html`).
    public func blogTagOutputFile(slug: String, page: Int, in outputDirectory: URL) -> URL {
        outputFile(forSegments: ["tags", slug] + pageComponents(page), in: outputDirectory)
    }

    /// Site-relative URL of the authors index: `/authors/`.
    public func blogAuthorsURLPath() -> String {
        basePath + "/authors/"
    }

    /// On-disk file for the authors index (`authors/index.html`).
    public func blogAuthorsOutputFile(in outputDirectory: URL) -> URL {
        outputFile(forSegments: ["authors"], in: outputDirectory)
    }

    /// Site-relative URL of an author page: `/authors/<slug>/`, then `/authors/<slug>/2/`…
    public func blogAuthorURLPath(slug: String, page: Int) -> String {
        basePath + "/authors/" + slug + "/" + pageSegment(page)
    }

    /// On-disk file for an author page (`authors/<slug>/index.html`, or `…/N/index.html`).
    public func blogAuthorOutputFile(slug: String, page: Int, in outputDirectory: URL) -> URL {
        outputFile(forSegments: ["authors", slug] + pageComponents(page), in: outputDirectory)
    }

    /// Site-relative URL of the RSS feed: `/feed.rss`.
    public func feedURLPath() -> String {
        basePath + "/feed.rss"
    }

    // MARK: - Private

    /// `""` for page 1, else `"N/"` — the trailing path segment for a page number.
    private func pageSegment(_ page: Int) -> String {
        page <= 1 ? "" : "\(page)/"
    }

    /// Path components for a page number (none for page 1, else `["N"]`).
    private func pageComponents(_ page: Int) -> [String] {
        page <= 1 ? [] : ["\(page)"]
    }

    /// Build an `…/index.html` output file from directory segments under the
    /// output root.
    private func outputFile(forSegments segments: [String], in outputDirectory: URL) -> URL {
        var url = outputDirectory
        for segment in segments {
            url.appendPathComponent(segment, isDirectory: true)
        }
        url.appendPathComponent("index.html", isDirectory: false)
        return url
    }
}
