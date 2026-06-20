// JSONSerialization (full Foundation) builds the JSON so page-derived strings
// are escaped correctly, rather than hand-assembling JSON in a Leaf template.
import Foundation

/// Builds the JSON-LD `@graph` emitted in a `<script type="application/ld+json">`.
///
/// Currently an `Organization` (the publisher entity — name, logo, social
/// profiles) plus a `WebSite`, which together establish the site's identity for
/// search engines and AI agents. Returns `nil` when no organization is configured.
enum StructuredData {
    static func jsonLD(
        siteName: String,
        siteURL: String,
        locale: String,
        organization: Organization?
    ) -> String? {
        guard let organization else { return nil }

        let siteBase = trimmingTrailingSlash(siteURL)
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

        let website: [String: Any] = [
            "@type": "WebSite",
            "@id": siteBase + "/#website",
            "name": siteName,
            "url": siteBase + "/",
            "inLanguage": locale,
            "publisher": ["@id": orgID],
        ]

        let document: [String: Any] = [
            "@context": "https://schema.org",
            "@graph": [org, website],
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

    private static func trimmingTrailingSlash(_ s: String) -> String {
        s.hasSuffix("/") ? String(s.dropLast()) : s
    }
}
