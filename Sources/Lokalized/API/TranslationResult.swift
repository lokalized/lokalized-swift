/// Immutable result with retained match and error references.
public final class TranslationResult: Sendable {
    /// The exact key requested by the caller.
    public let key: ExactString
    /// The rendered catalog translation or the final failure handler's display text.
    public let translation: String
    /// The requested or selected locale used to begin lookup.
    public let lookupLocale: LocaleTag
    /// The negotiation result associated with this lookup, when available.
    public let localeMatchResult: LocaleMatchResult?
    /// The catalog locale that supplied the translation, or `nil` for failure-handler text.
    public let resolvedLocale: LocaleTag?
    /// The locale candidates attempted, in lookup order.
    public let attemptedLocales: [LocaleTag]
    /// Whether the text came from a catalog, the requested key, or a handler replacement.
    public let status: TranslationResultStatus
    /// The final failure category, or `nil` for a successful catalog translation.
    public let failureReason: TranslationFailureReason?
    /// The retained resolution error, if the final failure was an evaluation failure.
    public let cause: (any Error)?

    /// Creates a lookup result and validates its outcome.
    ///
    /// A translated result requires a resolved attempted locale and no failure reason or cause.
    /// Handler text requires a failure reason and no resolved locale; a resolution failure requires a cause.
    /// Invalid locale tags, repeated attempted locales, or inconsistent outcomes throw `TranslationEvaluationError`.
    public init(key: ExactString, translation: String, lookupLocale: LocaleTag,
                localeMatchResult: LocaleMatchResult? = nil, resolvedLocale: LocaleTag?, attemptedLocales: [LocaleTag],
                status: TranslationResultStatus, failureReason: TranslationFailureReason? = nil, cause: (any Error)? = nil) throws {
        self.key = key; self.translation = translation
        self.lookupLocale = try TranslationContractValidation.locale(lookupLocale, description: "Lookup locale")
        self.localeMatchResult = localeMatchResult
        self.resolvedLocale = try resolvedLocale.map { try TranslationContractValidation.locale($0, description: "Resolved locale") }
        self.attemptedLocales = try TranslationContractValidation.attemptedLocales(attemptedLocales)
        self.status = status; self.failureReason = failureReason; self.cause = cause
        if status == .translated && (resolvedLocale == nil || failureReason != nil || cause != nil) {
            throw TranslationContractValidation.argument("A translated result requires a resolved locale and no failure outcome")
        }
        if status != .translated && (resolvedLocale != nil || failureReason == nil) {
            throw TranslationContractValidation.argument("A failure-handler result requires a failure reason and no resolved locale")
        }
        if status == .translated && !attemptedLocales.contains(where: { $0 == resolvedLocale }) {
            throw TranslationContractValidation.argument("A translated result's resolved locale must be present in attempted locales")
        }
        if status != .translated && ((failureReason == .resolutionFailure) != (cause != nil)) {
            throw TranslationContractValidation.argument("A failure result must carry a cause if and only if its reason is RESOLUTION_FAILURE")
        }
    }

    /// Whether negotiation used a fallback strategy or a different locale supplied
    /// the translation. Unmatched, CLDR-parent, likely-subtag, and primary-language
    /// selections count as fallback; a resolved locale that is not CLDR-equivalent
    /// to the lookup locale also counts.
    ///
    /// This can be true on the first attempted candidate. A fallback observer
    /// runs only when an earlier candidate failed before a later one succeeded.
    public var isFallback: Bool {
        if let match = localeMatchResult {
            switch match.matchType {
            case .noMatch, .cldrFallback, .likelySubtag, .primaryLanguage: return true
            case .exact, .canonical, .extendedRange, .wildcard: break
            }
        }
        return resolvedLocale.map { !CldrLocaleData.equivalentTags(lookupLocale.tag, $0.tag) } ?? false
    }
}
