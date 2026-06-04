#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Yams

/// An optional YAML front-matter block at the top of a markdown file
/// (the MkDocs `meta` extension), e.g.:
///
/// ```markdown
/// ---
/// title: Custom Page Title
/// description: A short summary.
/// ---
/// ```
public struct FrontMatter: Sendable, Equatable {
    /// All key/value pairs, stringified for use in templates.
    public var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public var title: String? { values["title"] }
    public var description: String? { values["description"] }
    /// An optional Leaf template name override (e.g. `template: landing`).
    public var template: String? { values["template"] }

    public static let empty = FrontMatter()
}

extension FrontMatter {
    /// Split a markdown source into its front matter (if any) and body.
    static func parse(from source: String) -> (frontMatter: FrontMatter, body: String) {
        guard source.hasPrefix("---\n") || source.hasPrefix("---\r\n") else {
            return (.empty, source)
        }

        let lines = source.components(separatedBy: "\n")
        // Find the closing delimiter after the opening one on line 0.
        guard let closingIndex = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            return (.empty, source)
        }

        let yamlLines = lines[1..<closingIndex]
        let bodyLines = lines[(closingIndex + 1)...]
        let yaml = yamlLines.joined(separator: "\n")
        let body = bodyLines.joined(separator: "\n")

        guard
            let loaded = try? Yams.load(yaml: yaml),
            let dictionary = loaded as? [String: Any]
        else {
            return (.empty, body)
        }

        var values: [String: String] = [:]
        for (key, value) in dictionary {
            values[key] = stringify(value)
        }
        return (FrontMatter(values: values), body)
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String: return string
        case let bool as Bool: return bool ? "true" : "false"
        case let int as Int: return String(int)
        case let double as Double: return String(double)
        default: return String(describing: value)
        }
    }
}
