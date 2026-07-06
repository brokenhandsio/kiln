/// A documentation language, identified by its locale code and a default
/// display name (the language's autonym).
///
/// Use one of the built-in cases, or ``custom(code:name:)`` for a locale Kiln
/// doesn't list yet:
///
/// ```swift
/// Language(.english, isDefault: true)
/// Language(.german)
/// Language(.custom(code: "gd", name: "Gàidhlig"))
/// ```
public enum LanguageCode: Sendable, Equatable {
    case english
    case german
    case spanish
    case french
    case italian
    case japanese
    case korean
    case dutch
    case polish
    case chinese                // Simplified Chinese
    case traditionalChinese
    case portuguese
    case brazilianPortuguese
    case russian
    case ukrainian
    case turkish
    case arabic
    case hindi
    case indonesian
    case vietnamese
    case thai
    case czech
    case swedish
    case norwegian              // Bokmål
    case danish
    case finnish
    case greek
    case hebrew
    case hungarian
    case romanian

    /// A locale Kiln doesn't have a built-in case for. `code` is used in
    /// filenames/URLs; `name` is the display name in the language switcher.
    case custom(code: String, name: String)

    /// The locale code used for content filename suffixes and URL prefixes
    /// (e.g. `"en"`, `"zh"`, `"pt-BR"`).
    public var code: String {
        switch self {
        case .english: return "en"
        case .german: return "de"
        case .spanish: return "es"
        case .french: return "fr"
        case .italian: return "it"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .dutch: return "nl"
        case .polish: return "pl"
        case .chinese: return "zh"
        case .traditionalChinese: return "zh-Hant"
        case .portuguese: return "pt"
        case .brazilianPortuguese: return "pt-BR"
        case .russian: return "ru"
        case .ukrainian: return "uk"
        case .turkish: return "tr"
        case .arabic: return "ar"
        case .hindi: return "hi"
        case .indonesian: return "id"
        case .vietnamese: return "vi"
        case .thai: return "th"
        case .czech: return "cs"
        case .swedish: return "sv"
        case .norwegian: return "nb"
        case .danish: return "da"
        case .finnish: return "fi"
        case .greek: return "el"
        case .hebrew: return "he"
        case .hungarian: return "hu"
        case .romanian: return "ro"
        case .custom(let code, _): return code
        }
    }

    /// The default display name (the language's autonym).
    public var name: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .french: return "Français"
        case .italian: return "Italiano"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .dutch: return "Nederlands"
        case .polish: return "Polski"
        case .chinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .portuguese: return "Português"
        case .brazilianPortuguese: return "Português (Brasil)"
        case .russian: return "Русский"
        case .ukrainian: return "Українська"
        case .turkish: return "Türkçe"
        case .arabic: return "العربية"
        case .hindi: return "हिन्दी"
        case .indonesian: return "Bahasa Indonesia"
        case .vietnamese: return "Tiếng Việt"
        case .thai: return "ไทย"
        case .czech: return "Čeština"
        case .swedish: return "Svenska"
        case .norwegian: return "Norsk"
        case .danish: return "Dansk"
        case .finnish: return "Suomi"
        case .greek: return "Ελληνικά"
        case .hebrew: return "עברית"
        case .hungarian: return "Magyar"
        case .romanian: return "Română"
        case .custom(_, let name): return name
        }
    }

    /// Whether this language is written right-to-left. Drives the `dir="rtl"`
    /// attribute on the page shell and the direction-aware theme CSS.
    ///
    /// Kiln can't infer direction for ``custom(code:name:)`` locales, so those
    /// default to left-to-right — pass `isRTL:` to ``Language/init(_:isRTL:...)``
    /// to override (e.g. `Language(.custom(code: "fa", name: "فارسی"), isRTL: true)`).
    public var isRTL: Bool {
        switch self {
        case .arabic, .hebrew:
            return true
        default:
            return false
        }
    }
}
