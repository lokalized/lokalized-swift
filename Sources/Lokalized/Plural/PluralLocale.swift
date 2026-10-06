/// A plural API received a malformed IETF BCP 47 locale tag.
public struct PluralLocaleError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The locale tag that could not be evaluated.
    public let locale: String
    /// The diagnostic explanation of the locale failure.
    public let message: String
    /// The diagnostic message.
    public var description: String { message }

    package init(locale: String) {
        self.locale = locale
        self.message = "Locale '\(locale)' is not a well-formed BCP 47 language tag"
    }
}

/// Shared JDK ingress and CLDR canonical candidate walk; every classifier and
/// catalog warning now observes the same pinned locale kernel.
package struct PluralLocale: Sendable {
    package let tag: String
    package let candidates: [String]

    package init(_ input: String) throws {
        do {
            let locale = try LocaleTag(input)
            tag = locale.tag
            // CLDR's internal root locale is exposed by the plural API as `und`.
            candidates = try CldrLocaleData.pluralCandidateTags(for: locale).map { $0 == "root" ? "und" : $0 }
        } catch is LocaleTagError {
            throw PluralLocaleError(locale: input)
        }
    }
}
