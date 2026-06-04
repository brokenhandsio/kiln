import Foundation

/// A contiguous region of a markdown document: either plain markdown or an
/// admonition block whose (indented) body is itself markdown.
enum MarkdownSegment {
    case markdown(String)
    case admonition(Admonition)
}

/// A parsed `!!!` / `???` admonition block.
struct Admonition {
    /// The admonition kind, e.g. `tip`, `note`, `warning`. The first token is
    /// used as the CSS modifier class; any extra tokens are appended as classes.
    var classes: [String]
    /// The rendered title. `nil` means "use the default (capitalised kind)";
    /// an empty string means "no title".
    var title: String?
    /// `true` for `???` collapsible blocks (rendered as `<details>`).
    var collapsible: Bool
    /// `true` for `???+` blocks that start expanded.
    var expanded: Bool
    /// The dedented body (markdown).
    var body: String

    var primaryKind: String { classes.first ?? "note" }
}

/// Splits a markdown document into plain-markdown and admonition segments.
///
/// MkDocs/Python-Markdown admonitions aren't part of CommonMark, so we extract
/// them before handing the surrounding text to `swift-markdown`. Bodies are
/// dedented and rendered recursively, which means admonitions can nest.
enum AdmonitionParser {
    static func segments(from source: String) -> [MarkdownSegment] {
        // Matches an admonition opener: `!!! kind ["Title"]` or `???[+] kind ["Title"]`.
        // Built locally because `Regex` isn't `Sendable` and so can't be a stored global.
        let openerPattern = #/^(?<marker>!!!|\?\?\?\+?)[ \t]+(?<kinds>[A-Za-z][\w\- ]*?)(?:[ \t]+"(?<title>[^"]*)")?[ \t]*$/#
        let lines = source.components(separatedBy: "\n")
        var segments: [MarkdownSegment] = []
        var plainBuffer: [String] = []

        func flushPlain() {
            if !plainBuffer.isEmpty {
                segments.append(.markdown(plainBuffer.joined(separator: "\n")))
                plainBuffer.removeAll()
            }
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let match = line.wholeMatch(of: openerPattern) {
                let marker = String(match.output.marker)
                let kinds = String(match.output.kinds)
                    .split(whereSeparator: { $0 == " " || $0 == "\t" })
                    .map(String.init)
                let title = match.output.title.map(String.init)

                // Collect the indented body that follows.
                var bodyLines: [String] = []
                var lookahead = index + 1
                while lookahead < lines.count {
                    let candidate = lines[lookahead]
                    if candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                        bodyLines.append("")
                        lookahead += 1
                    } else if let dedented = dedent(candidate) {
                        bodyLines.append(dedented)
                        lookahead += 1
                    } else {
                        break
                    }
                }

                // Trim leading/trailing blank lines from the body.
                while bodyLines.first?.isEmpty == true { bodyLines.removeFirst() }
                while bodyLines.last?.isEmpty == true { bodyLines.removeLast() }

                flushPlain()
                segments.append(.admonition(Admonition(
                    classes: kinds.isEmpty ? ["note"] : kinds,
                    title: title,
                    collapsible: marker.hasPrefix("???"),
                    expanded: marker == "???+",
                    body: bodyLines.joined(separator: "\n")
                )))
                index = lookahead
            } else {
                plainBuffer.append(line)
                index += 1
            }
        }
        flushPlain()
        return segments
    }

    /// Remove one level of indentation (4 spaces or a tab) from a body line.
    /// Returns `nil` if the line isn't indented (i.e. the body has ended).
    private static func dedent(_ line: String) -> String? {
        if line.hasPrefix("    ") {
            return String(line.dropFirst(4))
        } else if line.hasPrefix("\t") {
            return String(line.dropFirst(1))
        }
        return nil
    }
}
