// JSONSerialization (full Foundation) builds the JSON so page-derived strings
// are escaped correctly, rather than hand-assembling JSON in a Leaf template.
import Foundation

/// Builds the JSON-LD `@graph` emitted in a `<script type="application/ld+json">`.
///
/// Currently an `Organization` (the publisher entity — name, logo, social
/// profiles) plus a `WebSite`, which together establish the site's identity for
/// search engines and AI agents. Returns `nil` when no organization is configured.
/// One crumb in a breadcrumb trail (`url` is nil for sections without a landing page).
struct BreadcrumbItem: Sendable {
    let name: String
    let url: String?
}

/// One author of an article, rendered as a JSON-LD `Person`.
struct ArticleAuthor: Sendable {
    var name: String
    /// Profile URL (`Person.url`), if known.
    var url: String?
    /// Social/profile URLs (`Person.sameAs`).
    var sameAs: [String]
}

/// A single article/post entity (e.g. a blog post) for an `Article`-family
/// JSON-LD node. Built per post and linked to the site's `Organization`/`WebSite`.
struct ArticleStructuredData: Sendable {
    /// The schema.org type, e.g. `"BlogPosting"`.
    var type: String
    var headline: String
    /// The article's canonical absolute URL.
    var url: String
    /// ISO-8601 publication timestamp.
    var datePublished: String
    /// ISO-8601 last-modified timestamp (defaults to `datePublished` when nil).
    var dateModified: String?
    var authors: [ArticleAuthor]
    /// Absolute image URL (the social/OpenGraph image), if any.
    var image: String?
    var description: String?
    /// Tag names, emitted as schema.org `keywords`.
    var keywords: [String]
}

/// A person an author page is about, rendered as a `ProfilePage` + `Person`.
struct ProfileStructuredData: Sendable {
    var name: String
    /// The author page's absolute URL.
    var url: String
    /// Absolute avatar URL, if any.
    var image: String?
    var description: String?
    /// Social/profile URLs (`Person.sameAs`).
    var sameAs: [String]
}

enum StructuredData {
    static func jsonLD(
        siteName: String,
        siteURL: String,
        locale: String,
        organization: Organization?,
        breadcrumb: [BreadcrumbItem] = [],
        article: ArticleStructuredData? = nil,
        profile: ProfileStructuredData? = nil
    ) -> String? {
        // Emit if we have an organization (Org+WebSite), a breadcrumb, an article,
        // or an author profile.
        guard organization != nil || !breadcrumb.isEmpty || article != nil || profile != nil else { return nil }

        let siteBase = trimmingTrailingSlash(siteURL)
        let websiteID = siteBase + "/#website"
        // The publisher `@id` (also referenced by the article), present only when
        // an organization is configured.
        let orgID: String? = organization.map { trimmingTrailingSlash($0.url ?? siteURL) + "/#organization" }
        var graph: [[String: Any]] = []

        if let organization, let orgID {
            let orgBase = trimmingTrailingSlash(organization.url ?? siteURL)
            var org: [String: Any] = [
                "@type": "Organization",
                "@id": orgID,
                "name": organization.name ?? siteName,
                "url": orgBase + "/",
            ]
            if let logo = organization.logo {
                org["logo"] = ["@type": "ImageObject", "url": logo]
            }
            if !organization.sameAs.isEmpty {
                org["sameAs"] = organization.sameAs
            }
            graph.append(org)
            graph.append([
                "@type": "WebSite",
                "@id": websiteID,
                "name": siteName,
                "url": siteBase + "/",
                "inLanguage": locale,
                "publisher": ["@id": orgID],
            ])
        }

        if let article {
            var node: [String: Any] = [
                "@type": article.type,
                "@id": article.url + "#article",
                "headline": article.headline,
                "url": article.url,
                "mainEntityOfPage": ["@type": "WebPage", "@id": article.url],
                "datePublished": article.datePublished,
                "dateModified": article.dateModified ?? article.datePublished,
                "inLanguage": locale,
            ]
            if !article.authors.isEmpty {
                node["author"] = article.authors.map { author -> [String: Any] in
                    var person: [String: Any] = ["@type": "Person", "name": author.name]
                    if let url = author.url { person["url"] = url }
                    if !author.sameAs.isEmpty { person["sameAs"] = author.sameAs }
                    return person
                }
            }
            if let image = article.image { node["image"] = image }
            if let description = article.description { node["description"] = description }
            if !article.keywords.isEmpty { node["keywords"] = article.keywords.joined(separator: ", ") }
            // Tie the article to the publisher + website when they exist.
            if let orgID {
                node["publisher"] = ["@id": orgID]
                node["isPartOf"] = ["@id": websiteID]
            }
            graph.append(node)
        }

        if let profile {
            var person: [String: Any] = [
                "@type": "Person",
                "@id": profile.url + "#person",
                "name": profile.name,
                "url": profile.url,
            ]
            if let image = profile.image { person["image"] = image }
            if let description = profile.description { person["description"] = description }
            if !profile.sameAs.isEmpty { person["sameAs"] = profile.sameAs }
            graph.append(person)

            var profilePage: [String: Any] = [
                "@type": "ProfilePage",
                "@id": profile.url + "#profilepage",
                "url": profile.url,
                "name": profile.name,
                "mainEntity": ["@id": profile.url + "#person"],
            ]
            if organization != nil { profilePage["isPartOf"] = ["@id": websiteID] }
            graph.append(profilePage)
        }

        if !breadcrumb.isEmpty {
            // Position 1 is the site home; the trail (sections → current page) follows.
            var elements: [[String: Any]] = [
                listItem(position: 1, name: siteName, url: siteBase + "/"),
            ]
            for (index, crumb) in breadcrumb.enumerated() {
                // Crumb URLs are site-relative (e.g. `/fluent/`) — make absolute;
                // pass through anything already absolute (external links).
                let item = crumb.url.map { url in
                    url.hasPrefix("http") ? url : siteBase + (url.hasPrefix("/") ? url : "/" + url)
                }
                elements.append(listItem(position: index + 2, name: crumb.name, url: item))
            }
            graph.append(["@type": "BreadcrumbList", "itemListElement": elements])
        }

        let document: [String: Any] = [
            "@context": "https://schema.org",
            "@graph": graph,
        ]

        guard
            let data = try? JSONSerialization.data(
                withJSONObject: document,
                options: [.sortedKeys, .withoutEscapingSlashes]
            ),
            let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }

    private static func listItem(position: Int, name: String, url: String?) -> [String: Any] {
        var item: [String: Any] = ["@type": "ListItem", "position": position, "name": name]
        // `item` (the URL) is optional for the last crumb; omit it for sections
        // that have no landing page.
        if let url { item["item"] = url }
        return item
    }

    private static func trimmingTrailingSlash(_ s: String) -> String {
        s.hasSuffix("/") ? String(s.dropLast()) : s
    }
}
