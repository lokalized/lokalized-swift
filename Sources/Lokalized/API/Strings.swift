/// Synchronous throwing translation and strict locale negotiation services.
public protocol Strings: LocaleMatcher {
    /// The typed final fallback locale configured for this strings instance.
    var fallbackLocaleTag: LocaleTag { get }
    /// The loaded catalog locales. This set does not enumerate negotiable aliases.
    var supportedLocales: Set<LocaleTag> { get }
    /// Resolves a key using the requested locale and configured fallback policy.
    ///
    /// - Parameters:
    ///   - key: Exact localized string identifier; literals preserve UTF-16 identity.
    ///   - placeholders: Typed application values used by expressions and interpolation.
    ///   - options: Per-call overrides; omitted settings inherit the instance.
    /// - Returns: The translation or the final failure handler's display text.
    /// - Throws: Lookup, evaluation, or application callback errors that are not
    ///   handled by the configured failure response.
    func get(_ key: ExactString, placeholders: PlaceholderValues, options: TranslationOptions) throws -> String
    /// Resolves a key and returns its text, locale selection, attempts, and outcome.
    /// Shares the lookup, callback, and throwing behavior of `get`.
    func getResult(_ key: ExactString, placeholders: PlaceholderValues, options: TranslationOptions) throws -> TranslationResult
    /// Returns exact keys present in one loaded locale without negotiating.
    /// Throws when the locale is malformed or has no loaded catalog.
    func getKeysForLocale(_ locale: LocaleTag) throws -> Set<ExactString>
    /// Returns source keys absent from the target catalog. Both locales must be loaded.
    func getMissingKeys(sourceLocale: LocaleTag, targetLocale: LocaleTag) throws -> Set<ExactString>
}

public extension Strings {
    /// Returns the text from `getResult`, using explicit values and per-call options.
    func get(_ key: ExactString, placeholders: PlaceholderValues, options: TranslationOptions) throws -> String {
        try getResult(key, placeholders: placeholders, options: options).translation
    }
    /// Translates with no placeholders or per-call overrides.
    func get(_ key: ExactString) throws -> String { try get(key, placeholders: .empty, options: .none) }
    /// Translates with the supplied placeholders and instance settings.
    func get(_ key: ExactString, placeholders: PlaceholderValues) throws -> String { try get(key, placeholders: placeholders, options: .none) }
    /// Translates with per-call overrides and no placeholders.
    func get(_ key: ExactString, options: TranslationOptions) throws -> String { try get(key, placeholders: .empty, options: options) }
    /// Returns lookup diagnostics with no placeholders or per-call overrides.
    func getResult(_ key: ExactString) throws -> TranslationResult { try getResult(key, placeholders: .empty, options: .none) }
    /// Returns lookup diagnostics with the supplied placeholders and instance settings.
    func getResult(_ key: ExactString, placeholders: PlaceholderValues) throws -> TranslationResult { try getResult(key, placeholders: placeholders, options: .none) }
    /// Returns lookup diagnostics with per-call overrides and no placeholders.
    func getResult(_ key: ExactString, options: TranslationOptions) throws -> TranslationResult { try getResult(key, placeholders: .empty, options: options) }
}
