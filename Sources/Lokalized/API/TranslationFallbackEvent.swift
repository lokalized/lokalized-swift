/// A later candidate supplied a translation after preceding candidates failed.
/// Construction validates exact typed identity and preserves immediate causes.
public final class TranslationFallbackEvent: Sendable {
    /// The translation key that succeeded after earlier candidates failed.
    public let key: ExactString
    /// The locale used to begin lookup.
    public let lookupLocale: LocaleTag
    /// The negotiation result associated with the successful lookup.
    public let localeMatchResult: LocaleMatchResult?
    /// All attempted candidates, ending with the locale that supplied the translation.
    public let attemptedLocales: [LocaleTag]
    /// The catalog locale that supplied the successful translation.
    public let resolvedLocale: LocaleTag
    /// The failures before the successful candidate, in attempted-locale order.
    public let precedingFailures: [PrecedingFailure]

    /// Creates an event from a successful translated result and its earlier failures.
    ///
    /// There must be one failure for every preceding attempted locale, in the same order, and the final attempted locale must supply the translation.
    /// Inconsistent inputs throw `TranslationEvaluationError`.
    public init(translationResult: TranslationResult, precedingFailures: [PrecedingFailure]) throws {
        guard translationResult.status == .translated else {
            throw TranslationContractValidation.argument("A fallback event requires a translated result")
        }
        let attempts = translationResult.attemptedLocales
        guard !precedingFailures.isEmpty && precedingFailures.count == attempts.count - 1 else {
            throw TranslationContractValidation.argument("A fallback event requires one failure for each preceding locale candidate")
        }
        guard let resolved = translationResult.resolvedLocale, resolved == attempts.last else {
            throw TranslationContractValidation.argument("The final attempted locale must supply the fallback translation")
        }
        for index in precedingFailures.indices {
            guard precedingFailures[index].locale == attempts[index] else {
                throw TranslationContractValidation.argument("Preceding failures must follow the attempted locale order")
            }
        }
        key = translationResult.key; lookupLocale = translationResult.lookupLocale
        localeMatchResult = translationResult.localeMatchResult; attemptedLocales = attempts
        resolvedLocale = resolved; self.precedingFailures = precedingFailures
    }

    /// One failed locale attempt preceding a successful fallback translation.
    public final class PrecedingFailure: Sendable {
        /// The locale of the failed candidate.
        public let locale: LocaleTag
        /// Why the candidate did not produce a translation.
        public let reason: TranslationFailureReason
        /// The candidate's immediate resolution error. Present only for `.resolutionFailure`.
        public let cause: (any Error)?
        /// Creates a failed-attempt record. A cause is required exactly when the reason is `.resolutionFailure`.
        /// Invalid locale tags or inconsistent cause information throw `TranslationEvaluationError`.
        public init(locale: LocaleTag, reason: TranslationFailureReason, cause: (any Error)? = nil) throws {
            self.locale = try TranslationContractValidation.locale(locale, description: "Attempted locale")
            self.reason = reason
            guard (reason == .resolutionFailure) == (cause != nil) else {
                throw TranslationContractValidation.argument("A preceding failure must carry a cause if and only if its reason is RESOLUTION_FAILURE")
            }
            self.cause = cause
        }
    }
}
