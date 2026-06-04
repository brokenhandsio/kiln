/// A single heading captured while rendering a page, used to build the
/// on-page table of contents.
public struct TOCEntry: Sendable, Equatable {
    /// Heading level (1 for `#`, 2 for `##`, …).
    public var level: Int
    /// The heading's anchor id (matches the `id` attribute on the heading).
    public var id: String
    /// The heading's plain-text title.
    public var title: String
    /// Nested headings (deeper levels appearing before the next sibling).
    public var children: [TOCEntry]

    public init(level: Int, id: String, title: String, children: [TOCEntry] = []) {
        self.level = level
        self.id = id
        self.title = title
        self.children = children
    }
}

enum TableOfContents {
    /// Build a nested tree from a flat, in-order list of headings, restricted to
    /// the configured level range.
    static func build(from headings: [TOCEntry], levels: ClosedRange<Int>) -> [TOCEntry] {
        let filtered = headings.filter { levels.contains($0.level) }
        var roots: [TOCEntry] = []
        // Stack of references into the tree we're building.
        var stack: [TOCEntry] = []

        func flush(downTo level: Int) {
            while let last = stack.last, last.level >= level {
                let finished = stack.removeLast()
                if var parent = stack.last {
                    parent.children.append(finished)
                    stack[stack.count - 1] = parent
                } else {
                    roots.append(finished)
                }
            }
        }

        for heading in filtered {
            flush(downTo: heading.level)
            stack.append(heading)
        }
        flush(downTo: Int.min + 1)
        return roots
    }
}
