import Testing
@testable import Kiln

@Suite("Configuration validation")
struct ConfigurationTests {
    @Test("A single default language validates")
    func validConfig() throws {
        let site = KilnSite(name: "Docs", url: "https://x.com", languages: [
            .init(.english, isDefault: true),
            .init(.german),
        ]) {
            Page("Home", "index.md")
        }
        try site.validate()
        #expect(site.defaultLanguage.locale == "en")
        #expect(site.buildableLanguages.count == 2)
    }

    @Test("No default language is rejected")
    func noDefault() {
        let site = KilnSite(name: "Docs", url: "https://x.com", languages: [
            .init(.english),
        ]) {
            Page("Home", "index.md")
        }
        #expect(throws: ConfigurationError.self) { try site.validate() }
    }

    @Test("Multiple default languages are rejected")
    func multipleDefaults() {
        let site = KilnSite(name: "Docs", url: "https://x.com", languages: [
            .init(.english, isDefault: true),
            .init(.german, isDefault: true),
        ]) {
            Page("Home", "index.md")
        }
        #expect(throws: ConfigurationError.self) { try site.validate() }
    }

    @Test("Non-buildable languages are excluded")
    func excludesNonBuildable() {
        let site = KilnSite(name: "Docs", url: "https://x.com", languages: [
            .init(.english, isDefault: true),
            .init(.french, build: false),
        ]) {
            Page("Home", "index.md")
        }
        #expect(site.buildableLanguages.map(\.locale) == ["en"])
    }

    @Test("Language codes carry the right writing direction")
    func languageCodeDirection() {
        #expect(LanguageCode.arabic.isRTL)
        #expect(LanguageCode.hebrew.isRTL)
        #expect(!LanguageCode.english.isRTL)
        #expect(!LanguageCode.german.isRTL)
        // Kiln can't classify a custom locale, so it defaults to LTR.
        #expect(!LanguageCode.custom(code: "fa", name: "فارسی").isRTL)
    }

    @Test("Language direction defaults from its code and is overridable")
    func languageDirection() {
        #expect(Language(.arabic).isRTL)
        #expect(!Language(.english, isDefault: true).isRTL)
        // A custom RTL locale can declare its direction explicitly.
        #expect(Language(.custom(code: "fa", name: "فارسی"), isRTL: true).isRTL)
        // …and an explicit value overrides the code's default either way.
        #expect(!Language(.arabic, isRTL: false).isRTL)
    }
}
