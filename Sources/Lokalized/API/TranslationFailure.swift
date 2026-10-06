/// The final failed lookup delivered to a `TranslationFailureHandler`.
/// Includes the requested key, placeholder values, attempted locales, failure
/// category, and first resolution error when one occurred.
public final class TranslationFailure: Sendable, CustomStringConvertible {
    /// The exact translation key requested by the caller.
    public let key: ExactString
    /// The requested or selected locale used to begin lookup.
    public let lookupLocale: LocaleTag
    /// The associated negotiation result, when available.
    public let localeMatchResult: LocaleMatchResult?
    /// The locale candidates attempted, in lookup order.
    public let attemptedLocales: [LocaleTag]
    /// A snapshot of the caller-supplied placeholder values.
    public let placeholders: PlaceholderValues
    /// The final failure category. A resolution error takes precedence over missing text or unmatched alternatives.
    public let reason: TranslationFailureReason
    /// The first retained resolution error, or `nil` when no resolution error occurred.
    public let cause: (any Error)?
    /// Creates a snapshot of a final failed lookup. The supplied attempt history and error are retained without additional validation.
    public init(key: ExactString, lookupLocale: LocaleTag, localeMatchResult: LocaleMatchResult? = nil,
                attemptedLocales: [LocaleTag], placeholders: PlaceholderValues, reason: TranslationFailureReason,
                cause: (any Error)? = nil) {
        self.key = key; self.lookupLocale = lookupLocale; self.localeMatchResult = localeMatchResult
        self.attemptedLocales = attemptedLocales; self.placeholders = placeholders; self.reason = reason; self.cause = cause
    }
    /// Does not expose placeholder values or invoke their display callbacks.
    public var message: String {
        "Unable to resolve translation key '\(key)' for locale '\(lookupLocale.tag)'. Reason: \(reason.displayName). Attempted locales: [\(attemptedLocales.map(\.tag).joined(separator: ", "))]"
    }
    /// A diagnostic summary that does not render or disclose placeholder values.
    public var description: String { message }
}
