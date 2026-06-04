import Testing
@testable import Kiln

@Suite("Configuration validation")
struct ConfigurationTests {
    @Test("A single default language validates")
    func validConfig() throws {
        let site = KilnSite(name: "Docs", url: "https://x.com", languages: [
            .init(locale: "en", name: "English", isDefault: true),
            .init(locale: "de", name: "Deutsch"),
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
            .init(locale: "en", name: "English"),
        ]) {
            Page("Home", "index.md")
        }
        #expect(throws: ConfigurationError.self) { try site.validate() }
    }

    @Test("Multiple default languages are rejected")
    func multipleDefaults() {
        let site = KilnSite(name: "Docs", url: "https://x.com", languages: [
            .init(locale: "en", name: "English", isDefault: true),
            .init(locale: "de", name: "Deutsch", isDefault: true),
        ]) {
            Page("Home", "index.md")
        }
        #expect(throws: ConfigurationError.self) { try site.validate() }
    }

    @Test("Non-buildable languages are excluded")
    func excludesNonBuildable() {
        let site = KilnSite(name: "Docs", url: "https://x.com", languages: [
            .init(locale: "en", name: "English", isDefault: true),
            .init(locale: "fr", name: "Français", build: false),
        ]) {
            Page("Home", "index.md")
        }
        #expect(site.buildableLanguages.map(\.locale) == ["en"])
    }
}
