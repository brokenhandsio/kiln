import Foundation

/// The portable branding subset of DocC's `theme-settings.json`.
/// Layout, fonts, backgrounds and feature flags remain the host theme's concern.
public struct DocCThemeSettings: Decodable, Sendable {
    /// Resolved colours for the documentation intro, including `var(--color-…)` aliases.
    public let accentLight: String?
    public let accentDark: String?
    /// The technology icon path as specified by DocC (resolved when rendering).
    public let technologyIcon: String?

    private struct Color: Decodable {
        let light: String?
        let dark: String?

        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let string = try? value.decode(String.self) {
                light = string
                dark = string
            } else {
                let variants = (try? value.decode([String: String].self)) ?? [:]
                light = variants["light"]
                dark = variants["dark"]
            }
        }
    }

    private struct Theme: Decodable {
        let color: [String: Color]?
        let icons: [String: String]?
    }
    private enum CodingKeys: String, CodingKey { case theme }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let theme = try container.decodeIfPresent(Theme.self, forKey: .theme)
        let colors = theme?.color ?? [:]
        func resolve(dark: Bool) -> String? {
            var key = "documentation-intro-accent"
            var visited: Set<String> = []
            while visited.insert(key).inserted, let color = colors[key] {
                guard let raw = dark ? (color.dark ?? color.light) : (color.light ?? color.dark) else { return nil }
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("var(--color-"), value.hasSuffix(")") {
                    key = String(value.dropFirst("var(--color-".count).dropLast())
                } else {
                    return Self.isColor(value) ? value : nil
                }
            }
            return nil
        }
        accentLight = resolve(dark: false)
        accentDark = resolve(dark: true)
        technologyIcon = theme?.icons?["technology"]
    }

    // Accept colour literals, not arbitrary CSS declarations, URLs or gradients.
    // Colours are exposed as data; the host theme chooses whether to use them.
    private static func isColor(_ value: String) -> Bool {
        let pattern = #"^(#[0-9a-fA-F]{3,4}|#[0-9a-fA-F]{6}|#[0-9a-fA-F]{8}|(?:rgb|rgba|hsl|hsla)\([0-9.,%+ /-]+\)|black|white|transparent)$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    static func load(from archive: URL, issues: inout [String]) -> DocCThemeSettings? {
        let file = archive.appendingPathComponent("theme-settings.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
        } catch {
            issues.append("failed to decode theme-settings.json: \(error)")
            return nil
        }
    }

    /// Rebase an archive-local icon onto Kiln's module/version URL. DocC themes
    /// often bake their original hosting prefix into `/sqlkit/images/SQLKit/…`.
    /// Only use files actually present in this archive; never manufacture a 404.
    func iconURL(archiveURL: URL, urls: DocCURLs) -> String? {
        guard let icon = technologyIcon,
              let components = URLComponents(string: icon),
              components.scheme == nil, components.host == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard !parts.contains(".."), !parts.contains("."),
              let start = parts.firstIndex(of: "images") else { return nil }
        let relative = parts[start...].joined(separator: "/")
        let root = archiveURL.resolvingSymlinksInPath().path + "/"
        let file = archiveURL.appendingPathComponent(relative).resolvingSymlinksInPath()
        guard file.path.hasPrefix(root),
              (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        let encoded = relative.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))) ?? String($0)
        }.joined(separator: "/")
        return urls.moduleRootURL + encoded
    }
}
