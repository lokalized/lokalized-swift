/// Immutable per-call overrides. Nil settings inherit instance configuration.
/// A direct locale, language ranges and supplied match are mutually exclusive.
public struct TranslationOptions: Hashable, Sendable {
    public let locale: LocaleTag?
    public let languageRanges: [LanguageRange]?
    public let localeMatchResult: LocaleMatchResult?
    public let bidiIsolation: BidiIsolation?
    public let translationFailureHandler: TranslationFailureHandler?
    public let translationFallbackPolicy: TranslationFallbackPolicy?
    public let translationFallbackObserver: TranslationFallbackObserver?
    public static let none = Self()

    public init() {
        locale = nil; languageRanges = nil; localeMatchResult = nil; bidiIsolation = nil
        translationFailureHandler = nil; translationFallbackPolicy = nil; translationFallbackObserver = nil
    }
    public init(locale: LocaleTag? = nil, languageRanges: [LanguageRange]? = nil, localeMatchResult: LocaleMatchResult? = nil,
                bidiIsolation: BidiIsolation? = nil, translationFailureHandler: TranslationFailureHandler? = nil,
                translationFallbackPolicy: TranslationFallbackPolicy? = nil,
                translationFallbackObserver: TranslationFallbackObserver? = nil) throws {
        guard [locale != nil, languageRanges != nil, localeMatchResult != nil].filter({ $0 }).count <= 1 else {
            throw TranslationContractValidation.argument("Specify either locale, languageRanges, or localeMatchResult, not more than one")
        }
        self.locale = try locale.map { try TranslationContractValidation.locale($0, description: "Locale override") }
        if let languageRanges, languageRanges.count > DefaultLocaleMatcher.maximumLanguageRanges {
            throw TranslationContractValidation.argument("At most \(DefaultLocaleMatcher.maximumLanguageRanges) language ranges are supported, but received \(languageRanges.count)")
        }
        self.languageRanges = languageRanges; self.localeMatchResult = localeMatchResult; self.bidiIsolation = bidiIsolation
        self.translationFailureHandler = translationFailureHandler; self.translationFallbackPolicy = translationFallbackPolicy
        self.translationFallbackObserver = translationFallbackObserver
    }
    public static func forLocale(_ locale: LocaleTag) throws -> Self { try Self(locale: locale) }
    public static func forLocale(_ locale: String) throws -> Self {
        try Self(locale: MatchingLocale.validated(locale, description: "Locale override"))
    }
    public static func forLanguageRanges(_ languageRanges: [LanguageRange]) throws -> Self { try Self(languageRanges: languageRanges) }
    public static func forLocaleMatch(_ localeMatchResult: LocaleMatchResult) -> Self {
        // The final public match class has already validated structural invariants.
        // Instance-dependent provenance validation remains at consumption.
        Self(validatedMatch: localeMatchResult)
    }
    private init(validatedMatch: LocaleMatchResult) {
        locale = nil; languageRanges = nil; localeMatchResult = validatedMatch; bidiIsolation = nil
        translationFailureHandler = nil; translationFallbackPolicy = nil; translationFallbackObserver = nil
    }
}
