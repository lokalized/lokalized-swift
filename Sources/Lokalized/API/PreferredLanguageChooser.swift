import Foundation

/// Ordered UI preferences, kept separate from weighted language-range negotiation.
/// Each invocation uses only its supplied preferences and matcher configuration.
public enum PreferredLanguageChooser {
    /// Raw entries count toward the cap, including malformed entries.
    public static let maximumPreferredLanguages = 32

    /// Returns the first genuine strict direct match among the first 32 entries.
    /// Malformed native locale tags are skipped. An exhausted list returns the
    /// matcher's empty-range no-match diagnostics with its resolved fallback.
    /// Errors from a custom matcher propagate without being swallowed.
    public static func chooseLocaleForPreferredLanguages(_ preferences: [String],
                                                         using matcher: any LocaleMatcher) throws -> LocaleMatchResult {
        for preference in preferences.prefix(maximumPreferredLanguages) {
            do {
                // Validate without passing the projected tag onward: normalizing
                // twice changes Java-compatible UND/private-use identity.
                _ = try LocaleTag(preference)
            } catch is LocaleTagError {
                continue
            }
            let result = try matcher.matchFor(preference)
            if result.isMatch { return result }
        }
        return try matcher.matchFor([LanguageRange]())
    }

    /// Samples Apple's ordered language preferences when this function is called.
    /// Foundation supplies input only; Lokalized's pinned matcher elects the locale.
    /// Read actor-owned per-view preferences on that actor and use the injectable
    /// method instead of capturing them in a shared synchronous locale supplier.
    public static func chooseAppleLocale(using matcher: any LocaleMatcher) throws -> LocaleMatchResult {
        try chooseLocaleForPreferredLanguages(Foundation.Locale.preferredLanguages, using: matcher)
    }
}
