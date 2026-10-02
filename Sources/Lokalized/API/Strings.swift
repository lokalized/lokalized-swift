/// Synchronous throwing translation and strict locale negotiation services.
public protocol Strings: LocaleMatcher {
    var fallbackLocaleTag: LocaleTag { get }
    var supportedLocales: Set<LocaleTag> { get }
    func get(_ key: ExactString, placeholders: PlaceholderValues, options: TranslationOptions) throws -> String
    func getResult(_ key: ExactString, placeholders: PlaceholderValues, options: TranslationOptions) throws -> TranslationResult
    func getKeysForLocale(_ locale: LocaleTag) throws -> Set<ExactString>
    func getMissingKeys(sourceLocale: LocaleTag, targetLocale: LocaleTag) throws -> Set<ExactString>
}

public extension Strings {
    func get(_ key: ExactString, placeholders: PlaceholderValues, options: TranslationOptions) throws -> String {
        try getResult(key, placeholders: placeholders, options: options).translation
    }
    func get(_ key: ExactString) throws -> String { try get(key, placeholders: .empty, options: .none) }
    func get(_ key: ExactString, placeholders: PlaceholderValues) throws -> String { try get(key, placeholders: placeholders, options: .none) }
    func get(_ key: ExactString, options: TranslationOptions) throws -> String { try get(key, placeholders: .empty, options: options) }
    func getResult(_ key: ExactString) throws -> TranslationResult { try getResult(key, placeholders: .empty, options: .none) }
    func getResult(_ key: ExactString, placeholders: PlaceholderValues) throws -> TranslationResult { try getResult(key, placeholders: placeholders, options: .none) }
    func getResult(_ key: ExactString, options: TranslationOptions) throws -> TranslationResult { try getResult(key, placeholders: .empty, options: options) }
}
