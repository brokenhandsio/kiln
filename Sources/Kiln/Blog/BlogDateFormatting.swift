// DateFormatter lives in full Foundation (not FoundationEssentials).
import Foundation

/// Date formatting for blog output. All formatters are pinned to `en_US_POSIX`
/// and UTC so output is identical regardless of the build machine's locale and
/// time zone. The blog is English-only, so the long form uses English ordinals.
enum BlogDateFormatting {
    /// Long, human form with an ordinal day, e.g. `"21st June 2024"` — the format
    /// used on post pages.
    static func long(_ date: Date) -> String {
        let day = Int(BlogLoader.formatter(format: "d").string(from: date)) ?? 0
        let rest = BlogLoader.formatter(format: "MMMM yyyy").string(from: date)
        return "\(day)\(ordinalSuffix(day)) \(rest)"
    }

    /// Short form using a caller-supplied format (e.g. `"d MMM yyyy"` → `"21 Jun 2024"`).
    static func short(_ date: Date, format: String) -> String {
        BlogLoader.formatter(format: format).string(from: date)
    }

    /// ISO-8601 calendar date (`"2024-06-21"`) for `<time datetime="…">`.
    static func iso(_ date: Date) -> String {
        BlogLoader.formatter(format: "yyyy-MM-dd").string(from: date)
    }

    /// RFC-822 date for RSS `<pubDate>` (e.g. `"Fri, 21 Jun 2024 18:00:00 +0000"`).
    static func rfc822(_ date: Date) -> String {
        BlogLoader.formatter(format: "EEE, dd MMM yyyy HH:mm:ss Z").string(from: date)
    }

    /// English ordinal suffix for a day number (`1 → "st"`, `2 → "nd"`, `11 → "th"`).
    static func ordinalSuffix(_ day: Int) -> String {
        let tens = (day % 100) / 10
        if tens == 1 { return "th" }    // 11th–13th
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
