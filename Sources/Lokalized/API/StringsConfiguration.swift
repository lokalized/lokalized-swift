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
    /// Supplies all immutable catalogs once during runtime construction.
    public let localizedStringSupplier: LocalizedStringSupplier?
    /// Supplies a requested locale per lookup; exactly one locale supplier kind is required.
    public let localeSupplier: LocaleSupplier?
    /// Supplies a negotiation result per lookup instead of a requested locale.
    public let localeMatchSupplier: LocaleMatchSupplier?
    /// Final fallback catalog locale. It must be present in the supplied catalogs.
    public let fallbackLocale: LocaleTag
    /// Ordered preferences used to resolve ambiguous catalog locales for a language.
    public let tiebreakerLocalesByLanguageCode: [String: [LocaleTag]]?
    /// Handles the final failed lookup; omission uses `returnKey()`.
    public let translationFailureHandler: TranslationFailureHandler?
    /// Decides whether a failed candidate permits trying the next locale.
    public let translationFallbackPolicy: TranslationFallbackPolicy?
    /// Observes a successful translation from a later candidate before it returns.
    public let translationFallbackObserver: TranslationFallbackObserver?
    /// Evaluation bounds; omission uses `TranslationRuntimeLimits.defaults`.
    public let runtimeLimits: TranslationRuntimeLimits?
    /// Resolves language-specific pronunciation categories for terms when needed.
    public let phoneticResolver: PhoneticResolver?
    /// Placeholder bidi isolation; omission uses `BidiIsolation.rtlLocales`.
    public let bidiIsolation: BidiIsolation?
    /// Equivalence data for parsing language ranges; omission uses the pinned IANA registry.
    public let languageRangeEquivalents: LanguageRangeEquivalents?

    /// Stores construction settings without invoking suppliers or validating catalogs.
    /// `DefaultStrings.init(configuration:)` performs validation and applies defaults.
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
