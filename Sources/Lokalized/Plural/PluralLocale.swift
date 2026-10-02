/// A plural classifier received a locale outside its accepted tag syntax.
/// The shared pinned locale kernel validates the supplied tag.
public struct PluralLocaleError: Error, Hashable, Sendable, CustomStringConvertible {
    public let locale: String
    public let message: String
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
