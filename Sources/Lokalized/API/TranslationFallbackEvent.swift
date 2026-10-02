/// A later candidate supplied a translation after preceding candidates failed.
/// Construction validates exact typed identity and preserves immediate causes.
public final class TranslationFallbackEvent: Sendable {
    public let key: ExactString
    public let lookupLocale: LocaleTag
    public let localeMatchResult: LocaleMatchResult?
    public let attemptedLocales: [LocaleTag]
    public let resolvedLocale: LocaleTag
    public let precedingFailures: [PrecedingFailure]

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

    public final class PrecedingFailure: Sendable {
        public let locale: LocaleTag
        public let reason: TranslationFailureReason
        public let cause: (any Error)?
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
