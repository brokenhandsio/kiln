import LeafKit

/// `#t("key")` — looks up a theme-defined localised string by key.
///
/// Resolves against the current language's ``Language/customStrings`` (already
/// merged with the default language's values in ``RenderContext``, so a key
/// that a translation hasn't provided still renders the default-language text).
/// If the key is unknown everywhere, the key itself is returned so a missing
/// translation is visible rather than blank.
struct TranslateTag: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        try ctx.requireParameterCount(1)
        guard let key = ctx.parameters[0].string else {
            throw LeafError(.unknownError(#"#t requires a string key, e.g. #t("tagline")"#))
        }
        let strings = ctx.data["customStrings"]?.dictionary ?? [:]
        return strings[key] ?? .string(key)
    }
}
