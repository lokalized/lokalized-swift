/// Supplies immutable catalogs once, when `DefaultStrings` is constructed.
public typealias LocalizedStringSupplier = @Sendable () throws -> [LocaleTag: LocalizedCatalog]
/// Supplies one requested locale for a lookup, with the current matcher context.
public typealias LocaleSupplier = @Sendable (any LocaleMatcher) throws -> LocaleTag
/// Supplies an existing negotiation result; its reference identity is retained.
public typealias LocaleMatchSupplier = @Sendable (any LocaleMatcher) throws -> LocaleMatchResult

/// Immutable construction inputs. Validation belongs to `DefaultStrings` so
/// invalid inputs retain the reference's construction and callback precedence.
/// Exactly one locale supplier kind is required by that constructor.
public struct StringsConfiguration: Sendable {
    public let localizedStringSupplier: LocalizedStringSupplier?
    public let localeSupplier: LocaleSupplier?
    public let localeMatchSupplier: LocaleMatchSupplier?
    public let fallbackLocale: LocaleTag
    public let tiebreakerLocalesByLanguageCode: [String: [LocaleTag]]?
    public let translationFailureHandler: TranslationFailureHandler?
    public let translationFallbackPolicy: TranslationFallbackPolicy?
    public let translationFallbackObserver: TranslationFallbackObserver?
    public let runtimeLimits: TranslationRuntimeLimits?
    public let phoneticResolver: PhoneticResolver?
    public let bidiIsolation: BidiIsolation?
    public let languageRangeEquivalents: LanguageRangeEquivalents?

    public init(localizedStringSupplier: LocalizedStringSupplier? = nil,
                localeSupplier: LocaleSupplier? = nil, localeMatchSupplier: LocaleMatchSupplier? = nil,
                fallbackLocale: LocaleTag, tiebreakerLocalesByLanguageCode: [String: [LocaleTag]]? = nil,
                translationFailureHandler: TranslationFailureHandler? = nil,
                translationFallbackPolicy: TranslationFallbackPolicy? = nil,
                translationFallbackObserver: TranslationFallbackObserver? = nil,
                runtimeLimits: TranslationRuntimeLimits? = nil, phoneticResolver: PhoneticResolver? = nil,
                bidiIsolation: BidiIsolation? = nil, languageRangeEquivalents: LanguageRangeEquivalents? = nil) {
        self.localizedStringSupplier = localizedStringSupplier; self.localeSupplier = localeSupplier
        self.localeMatchSupplier = localeMatchSupplier; self.fallbackLocale = fallbackLocale
        self.tiebreakerLocalesByLanguageCode = tiebreakerLocalesByLanguageCode
        self.translationFailureHandler = translationFailureHandler; self.translationFallbackPolicy = translationFallbackPolicy
        self.translationFallbackObserver = translationFallbackObserver; self.runtimeLimits = runtimeLimits
        self.phoneticResolver = phoneticResolver; self.bidiIsolation = bidiIsolation
        self.languageRangeEquivalents = languageRangeEquivalents
    }
}
