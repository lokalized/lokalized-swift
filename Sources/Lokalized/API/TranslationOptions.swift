/// Immutable per-call overrides. Nil settings inherit instance configuration.
/// A direct locale, language ranges and supplied match are mutually exclusive.
public struct TranslationOptions: Hashable, Sendable {
    /// A direct requested locale override, or `nil` to inherit locale selection.
    public let locale: LocaleTag?
    /// Preferences negotiated by the strings instance at lookup time, or `nil` when another selection mode applies.
    public let languageRanges: [LanguageRange]?
    /// An existing match used for this lookup. Its fallback and considered locales must match the strings instance.
    public let localeMatchResult: LocaleMatchResult?
    /// A placeholder isolation override, or `nil` to inherit the instance setting.
    public let bidiIsolation: BidiIsolation?
    /// A final failure callback override, or `nil` to inherit the instance callback.
    public let translationFailureHandler: TranslationFailureHandler?
    /// A locale continuation policy override, or `nil` to inherit the instance policy.
    public let translationFallbackPolicy: TranslationFallbackPolicy?
    /// A successful fallback observer override. `nil` inherits the instance observer.
    public let translationFallbackObserver: TranslationFallbackObserver?
    /// Options that inherit every setting from the strings instance.
    public static let none = Self()

    /// Creates options that inherit every setting from the strings instance.
    public init() {
        locale = nil; languageRanges = nil; localeMatchResult = nil; bidiIsolation = nil
        translationFailureHandler = nil; translationFallbackPolicy = nil; translationFallbackObserver = nil
    }
    /// Creates per-call overrides. Specify at most one of `locale`, `languageRanges`, or `localeMatchResult`.
    ///
    /// Omitted settings inherit the strings instance. More than 32 language ranges or conflicting selection modes throw `TranslationEvaluationError`.
    /// A supplied match is checked against the strings instance when consumed.
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
    /// Creates a direct locale override. Malformed locale inputs throw a validation error.
    public static func forLocale(_ locale: LocaleTag) throws -> Self { try Self(locale: locale) }
    /// Creates a direct locale override. Malformed locale inputs throw a validation error.
    public static func forLocale(_ locale: String) throws -> Self {
        try Self(locale: MatchingLocale.validated(locale, description: "Locale override"))
    }
    /// Creates language preferences to negotiate at lookup time. More than 32 ranges throws `TranslationEvaluationError`.
    public static func forLanguageRanges(_ languageRanges: [LanguageRange]) throws -> Self { try Self(languageRanges: languageRanges) }
    /// Negotiates preferences immediately with the supplied matcher and stores
    /// the resulting match. Use `forLanguageRanges(_:)` to defer negotiation
    /// until lookup. Invalid range counts or matcher errors propagate.
    public static func forLanguageRanges(_ languageRanges: [LanguageRange], using matcher: any LocaleMatcher) throws -> Self {
        _ = try Self(languageRanges: languageRanges)
        return forLocaleMatch(try matcher.matchFor(languageRanges))
    }
    /// Negotiates an already combined `Accept-Language` header and stores its match.
    /// Nil, blank, malformed, or oversized headers are treated as no preferences.
    /// The matcher's unmatched result retains its configured fallback.
    /// Other errors from a custom matcher propagate.
    public static func forAcceptLanguage(_ acceptLanguage: String?, using matcher: any LocaleMatcher) throws -> Self {
        forLocaleMatch(try matcher.matchFor(usableAcceptLanguageRanges(acceptLanguage, using: matcher)))
    }
    /// Creates an override from an existing negotiation result.
    /// The strings instance checks that the result's fallback and considered locales match its configuration when used.
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
