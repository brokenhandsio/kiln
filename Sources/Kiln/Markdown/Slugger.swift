/// Generates GitHub-style, unique slugs for heading anchors.
///
/// The same instance is reused across a single page so repeated heading text
/// gets a numeric suffix (`overview`, `overview-1`, …), matching the behaviour
/// readers expect from MkDocs/GitHub.
final class Slugger {
    private var seen: [String: Int] = [:]

    func slug(for text: String) -> String {
        let base = Slugger.normalise(text)
        let candidate = base.isEmpty ? "section" : base

        if let count = seen[candidate] {
            seen[candidate] = count + 1
            return "\(candidate)-\(count)"
        } else {
            seen[candidate] = 1
            return candidate
        }
    }

    /// Lowercase, replace whitespace with hyphens and strip characters that
    /// aren't letters, numbers, hyphens or underscores. Unicode letters (e.g.
    /// CJK, accented characters) are preserved so non-English headings still
    /// anchor. Implemented with the standard library only (no Foundation).
    static func normalise(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text.lowercased() {
            if character.isWhitespace {
                result.append("-")
            } else if character.isLetter || character.isNumber || character == "-" || character == "_" {
                result.append(character)
            }
            // everything else (punctuation, symbols) is dropped
        }
        // Collapse runs of hyphens and trim leading/trailing ones.
        return result
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }
}
