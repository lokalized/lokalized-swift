/// Immutable result with retained match and error references.
public final class TranslationResult: Sendable {
    public let key: ExactString
    public let translation: String
    public let lookupLocale: LocaleTag
    public let localeMatchResult: LocaleMatchResult?
    public let resolvedLocale: LocaleTag?
    public let attemptedLocales: [LocaleTag]
    public let status: TranslationResultStatus
    public let failureReason: TranslationFailureReason?
    public let cause: (any Error)?

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

    /// Negotiation fallback and per-key donor fallback are distinct from the
    /// successful-fallback observer's "later candidate" condition.
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
