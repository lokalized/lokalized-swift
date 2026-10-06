/// Raised by the throwing handler when the failure has no resolution cause.
/// A resolution failure rethrows its retained cause instead of constructing this.
public final class MissingTranslationError: Error, Sendable, CustomStringConvertible {
    /// The diagnostic explanation of the failed lookup.
    public let message: String
    /// The requested exact key.
    public let key: ExactString
    /// The locale used to begin lookup.
    public let lookupLocale: LocaleTag
    /// The negotiation result associated with the lookup, when available.
    public let localeMatchResult: LocaleMatchResult?
    /// The caller-supplied placeholder snapshot.
    public let placeholders: PlaceholderValues
    /// The final failed-lookup category.
    public let reason: TranslationFailureReason
    /// The locale candidates attempted, in lookup order.
    public let attemptedLocales: [LocaleTag]

    /// Creates a final lookup error from validated inputs or an existing failure snapshot.
    ///
    /// The lookup locale and attempted locales must be well formed, and attempted locales must not repeat. Invalid inputs throw `TranslationEvaluationError`.
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
    /// Creates a final lookup error from validated inputs or an existing failure snapshot.
    ///
    /// The lookup locale and attempted locales must be well formed, and attempted locales must not repeat. Invalid inputs throw `TranslationEvaluationError`.
    public convenience init(failure: TranslationFailure) throws {
        try self.init(message: failure.message, key: failure.key, placeholders: failure.placeholders,
                      lookupLocale: failure.lookupLocale, localeMatchResult: failure.localeMatchResult,
                      reason: failure.reason, attemptedLocales: failure.attemptedLocales)
    }
    /// The diagnostic message.
    public var description: String { message }
}
