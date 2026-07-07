/// A reusable "select" dropdown component, rendered to HTML — the shared basis
/// for the DocC sidebar's module and version switchers.
///
/// It's a native `<details>` disclosure (no JS): a pill toggle showing the
/// current value, and a panel of options (optionally grouped). Rendered in Swift
/// so every theme injects identical markup; CSS (`docc-select*`) styles it and a
/// `sizeClass` sizes it. Intended to migrate into the shared design system's
/// component library.
enum DocCSelect {
    /// One selectable option.
    struct Option: Sendable, Equatable {
        var label: String
        var url: String
        var isCurrent: Bool
        /// Optional pill badge (e.g. "beta") shown after the label.
        var badge: String? = nil
    }

    /// A group of options. `title == nil` renders the options ungrouped (flat).
    struct Section: Sendable, Equatable {
        var title: String?
        var options: [Option]
    }

    /// Render the select. Returns "" when there are no options.
    ///
    /// - Parameters:
    ///   - label: the current value shown on the toggle (e.g. the module name).
    ///   - sections: grouped or flat options.
    ///   - sizeClass: extra class(es) on the root (e.g. `"docc-select--sidebar"`).
    static func render(label: String, sections: [Section], sizeClass: String = "") -> String {
        guard sections.contains(where: { !$0.options.isEmpty }) else { return "" }
        let rootClass = sizeClass.isEmpty ? "docc-select" : "docc-select \(sizeClass)"

        var out = "<details class=\"\(rootClass)\">\n"
        out += "<summary class=\"docc-select-toggle\" aria-label=\"Select\">"
        out += "<span class=\"docc-select-value\">\(HTMLEscaping.text(label))</span>"
        // Self-contained chevron (doesn't depend on the theme's icon set); the
        // CSS rotates it when the disclosure is open.
        out += "<span class=\"docc-select-chevron\" aria-hidden=\"true\">"
        out += "<svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.25\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polyline points=\"6 9 12 15 18 9\"></polyline></svg>"
        out += "</span>"
        out += "</summary>\n<div class=\"docc-select-menu\">\n"
        for section in sections where !section.options.isEmpty {
            if let title = section.title {
                out += "<p class=\"docc-select-group\">\(HTMLEscaping.text(title))</p>\n"
            }
            for option in section.options {
                let currentClass = option.isCurrent ? " is-current" : ""
                out += "<a class=\"docc-select-option\(currentClass)\" href=\"\(HTMLEscaping.attribute(option.url))\">"
                out += HTMLEscaping.text(option.label)
                if let badge = option.badge {
                    out += " <span class=\"docc-select-badge\">\(HTMLEscaping.text(badge))</span>"
                }
                out += "</a>\n"
            }
        }
        out += "</div>\n</details>\n"
        return out
    }
}
