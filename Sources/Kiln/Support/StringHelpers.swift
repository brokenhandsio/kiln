// Standard-library string helpers used in place of Foundation's
// `trimmingCharacters(in:)` / `CharacterSet`, so the files that use them don't
// need to import Foundation (and work against FoundationEssentials on Linux).

extension StringProtocol {
    /// `true` if the string is empty or contains only whitespace.
    var isBlank: Bool {
        allSatisfy(\.isWhitespace)
    }

    /// Uppercase the first character, leaving the rest unchanged (a
    /// stdlib stand-in for Foundation's `capitalized`, sufficient for the
    /// single-word admonition kinds we use it on).
    var capitalizedFirstLetter: String {
        guard let first else { return String(self) }
        return first.uppercased() + dropFirst()
    }

    /// Return the string with leading and trailing whitespace removed.
    func trimmedWhitespace() -> String {
        var slice = Substring(self)
        while let first = slice.first, first.isWhitespace { slice = slice.dropFirst() }
        while let last = slice.last, last.isWhitespace { slice = slice.dropLast() }
        return String(slice)
    }

    /// Split into lines on `\n` (preserving empty lines), as `[String]`.
    func splitLines() -> [String] {
        String(self).split(separator: "\n" as Character, omittingEmptySubsequences: false).map(String.init)
    }
}
