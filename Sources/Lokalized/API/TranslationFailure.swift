/// One final failed lookup, with a shallow immutable caller-value snapshot.
/// Like Java's runtime failure record, this snapshots without revalidating the
/// attempted walk or discarding the first retained resolution cause.
public final class TranslationFailure: Sendable, CustomStringConvertible {
    public let key: ExactString
    public let lookupLocale: LocaleTag
    public let localeMatchResult: LocaleMatchResult?
    public let attemptedLocales: [LocaleTag]
    public let placeholders: PlaceholderValues
    public let reason: TranslationFailureReason
    public let cause: (any Error)?
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
    public var description: String { message }
}
