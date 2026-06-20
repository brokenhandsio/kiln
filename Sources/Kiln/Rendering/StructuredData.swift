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

enum StructuredData {
    static func jsonLD(
        siteName: String,
        siteURL: String,
        locale: String,
        organization: Organization?,
        breadcrumb: [BreadcrumbItem] = []
    ) -> String? {
        // Emit if we have either an organization (Org+WebSite) or a breadcrumb.
        guard organization != nil || !breadcrumb.isEmpty else { return nil }

        let siteBase = trimmingTrailingSlash(siteURL)
        var graph: [[String: Any]] = []

        if let organization {
            let orgBase = trimmingTrailingSlash(organization.url ?? siteURL)
            let orgID = orgBase + "/#organization"
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
                "@id": siteBase + "/#website",
                "name": siteName,
                "url": siteBase + "/",
                "inLanguage": locale,
                "publisher": ["@id": orgID],
            ])
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
