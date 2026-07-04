/// Builds an RSS 2.0 feed for the blog as a plain string (mirroring the sitemap
/// and robots.txt builders in ``SiteGenerator``).
enum RSSFeed {
    /// Render the feed XML.
    /// - Parameters:
    ///   - title: channel title.
    ///   - description: channel description.
    ///   - siteURL: the blog's home URL (channel `<link>`).
    ///   - feedURL: the absolute URL of this feed (for `atom:link rel="self"`).
    ///   - siteOrigin: the scheme+host (e.g. `https://blog.example.com`) used to
    ///     absolutise root-relative URLs in each post's body so links and images
    ///     resolve in feed readers.
    ///   - language: the feed language code (e.g. `"en"`).
    ///   - posts: posts to include, newest first.
    ///   - postURL: absolute URL for a given post.
    static func render(
        title: String,
        description: String,
        siteURL: String,
        feedURL: String,
        siteOrigin: String,
        language: String,
        posts: [BlogPost],
        postURL: (BlogPost) -> String
    ) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\" xmlns:content=\"http://purl.org/rss/1.0/modules/content/\">\n"
        xml += "  <channel>\n"
        xml += "    <title>\(escape(title))</title>\n"
        xml += "    <link>\(escape(siteURL))</link>\n"
        xml += "    <description>\(escape(description))</description>\n"
        xml += "    <language>\(escape(language))</language>\n"
        xml += "    <atom:link href=\"\(escapeAttribute(feedURL))\" rel=\"self\" type=\"application/rss+xml\"/>\n"
        for post in posts {
            let url = postURL(post)
            xml += "    <item>\n"
            xml += "      <title>\(escape(post.title))</title>\n"
            xml += "      <link>\(escape(url))</link>\n"
            xml += "      <guid isPermaLink=\"true\">\(escape(url))</guid>\n"
            xml += "      <pubDate>\(BlogDateFormatting.rfc822(post.date))</pubDate>\n"
            if !post.excerpt.isEmpty {
                xml += "      <description>\(cdata(post.excerpt))</description>\n"
            }
            // Full post body so readers show the whole article, not just the
            // excerpt. `content:encoded` is the standard element for rich HTML.
            if !post.contentHTML.isEmpty {
                xml += "      <content:encoded>\(cdata(absolutise(post.contentHTML, origin: siteOrigin)))</content:encoded>\n"
            }
            for tag in post.tags {
                xml += "      <category>\(escape(tag))</category>\n"
            }
            xml += "    </item>\n"
        }
        xml += "  </channel>\n"
        xml += "</rss>\n"
        return xml
    }

    private static func escape(_ string: String) -> String {
        HTMLEscaping.text(string)
    }

    private static func escapeAttribute(_ string: String) -> String {
        HTMLEscaping.attribute(string)
    }

    /// Wrap text in a CDATA section, splitting any `]]>` so it can't close early.
    private static func cdata(_ string: String) -> String {
        "<![CDATA[" + string.replacing("]]>", with: "]]]]><![CDATA[>") + "]]>"
    }

    /// Rewrite root-relative `href`/`src` URLs (`/foo`) to absolute (`origin/foo`)
    /// so a post's links and images resolve in feed readers, which have no page
    /// base URL to resolve against. Protocol-relative URLs (`//host`) and already-
    /// absolute URLs are left untouched.
    private static func absolutise(_ html: String, origin: String) -> String {
        html.replacing(#/(href|src)="/(?!/)/#) { match in
            "\(match.output.1)=\"\(origin)/"
        }
    }
}
