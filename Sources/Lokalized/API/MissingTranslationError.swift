/// Raised by the throwing handler when the failure has no resolution cause.
/// A resolution failure rethrows its retained cause instead of constructing this.
public final class MissingTranslationError: Error, Sendable, CustomStringConvertible {
    public let message: String
    public let key: ExactString
    public let lookupLocale: LocaleTag
    public let localeMatchResult: LocaleMatchResult?
    public let placeholders: PlaceholderValues
    public let reason: TranslationFailureReason
    public let attemptedLocales: [LocaleTag]

    public init(message: String, key: ExactString, placeholders: PlaceholderValues, lookupLocale: LocaleTag,
                localeMatchResult: LocaleMatchResult? = nil, reason: TranslationFailureReason = .missingTranslation,
                attemptedLocales: [LocaleTag]? = nil) throws {
        guard reason != .resolutionFailure else {
            throw TranslationContractValidation.argument("MissingTranslationException cannot represent a resolution failure cause")
        }
        self.message = message; self.key = key; self.placeholders = placeholders
        self.lookupLocale = try TranslationContractValidation.locale(lookupLocale, description: "Lookup locale")
        self.localeMatchResult = localeMatchResult; self.reason = reason
        self.attemptedLocales = try TranslationContractValidation.attemptedLocales(attemptedLocales ?? [lookupLocale])
    }
    public convenience init(failure: TranslationFailure) throws {
        try self.init(message: failure.message, key: failure.key, placeholders: failure.placeholders,
                      lookupLocale: failure.lookupLocale, localeMatchResult: failure.localeMatchResult,
                      reason: failure.reason, attemptedLocales: failure.attemptedLocales)
    }
    public var description: String { message }
}
