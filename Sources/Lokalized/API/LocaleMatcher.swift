/// Locale negotiation and parsing of weighted language preferences.
///
/// `matchFor` returns selection diagnostics, including an unmatched outcome.
/// `bestMatchFor` returns the selected locale or the configured fallback. The
/// Accept-Language convenience method treats unusable headers as no preferences.
public protocol LocaleMatcher: Sendable {
    /// The final fallback locale returned by convenience methods when negotiation finds no match.
    var fallbackLocale: String { get }
    /// Negotiates one well-formed requested locale and returns selection diagnostics.
    /// Malformed input throws a validation error. An unmatched result retains the configured fallback without reporting a match.
    func matchFor(_ locale: String) throws -> LocaleMatchResult
    /// Negotiates weighted language ranges against the supported locales.
    /// Accepts at most 32 ranges and returns an unmatched result when none selects a locale; the configured fallback is still available.
    /// Invalid range counts throw `LocaleMatcherError`.
    func matchFor(_ languageRanges: [LanguageRange]) throws -> LocaleMatchResult
    /// Returns the selected supported locale, or the configured fallback when negotiation is unmatched.
    /// Invalid locale input or excessive range counts throw a validation error.
    func bestMatchFor(_ locale: String) throws -> String
    /// Returns the selected supported locale, or the configured fallback when negotiation is unmatched.
    /// Invalid locale input or excessive range counts throw a validation error.
    func bestMatchFor(_ languageRanges: [LanguageRange]) throws -> String
    /// Returns the best locale for an already combined `Accept-Language` header, or the configured fallback.
    ///
    /// Nil, blank, malformed, or oversized headers are treated as no preferences. Limits are 4,096 UTF-16 code units and 32 parsed ranges.
    /// Errors from custom implementations other than `LanguageRangeError` propagate.
    func bestMatchForAcceptLanguage(_ acceptLanguage: String?) throws -> String
    /// Strictly parses a weighted language preference list and expands equivalent tags.
    /// Malformed input throws `LanguageRangeError`. The default protocol implementation uses the bundled IANA table; `DefaultLocaleMatcher` uses its configured table.
    func parseLanguageRanges(_ ranges: String) throws -> [LanguageRange]
}

public extension LocaleMatcher {
    /// Negotiates one well-formed requested locale and returns selection diagnostics.
    /// Malformed input throws a validation error. An unmatched result retains the configured fallback without reporting a match.
    func matchFor(_ locale: String) throws -> LocaleMatchResult {
        let tag = try MatchingLocale.validated(locale, description: "Requested locale").tag
        return try matchFor([LanguageRange(tag)])
    }

    /// Negotiates one well-formed requested locale and returns selection diagnostics.
    /// Malformed input throws a validation error. An unmatched result retains the configured fallback without reporting a match.
    func matchFor(_ locale: LocaleTag) throws -> LocaleMatchResult {
        try JDKLocaleTag.requireWellFormed(locale, description: "Requested locale")
        return try matchFor([LanguageRange(locale.tag)])
    }

    /// Returns the selected supported locale, or the configured fallback when negotiation is unmatched.
    /// Invalid locale input or excessive range counts throw a validation error.
    func bestMatchFor(_ locale: String) throws -> String { try matchFor(locale).locale ?? fallbackLocale }
    /// Returns the selected supported locale, or the configured fallback when negotiation is unmatched.
    /// Invalid locale input or excessive range counts throw a validation error.
    func bestMatchFor(_ locale: LocaleTag) throws -> String { try matchFor(locale).locale ?? fallbackLocale }
    /// Returns the selected supported locale, or the configured fallback when negotiation is unmatched.
    /// Invalid locale input or excessive range counts throw a validation error.
    func bestMatchFor(_ languageRanges: [LanguageRange]) throws -> String { try matchFor(languageRanges).locale ?? fallbackLocale }

    /// Strictly parses a weighted language preference list and expands equivalent tags.
    /// Malformed input throws `LanguageRangeError`. The default protocol implementation uses the bundled IANA table; `DefaultLocaleMatcher` uses its configured table.
    func parseLanguageRanges(_ ranges: String) throws -> [LanguageRange] {
        try LanguageRangeParser.parse(ranges, equivalents: .ianaRegistry)
    }

    /// Returns the best locale for an already combined `Accept-Language` header, or the configured fallback.
    ///
    /// Nil, blank, malformed, or oversized headers are treated as no preferences. Limits are 4,096 UTF-16 code units and 32 parsed ranges.
    /// Errors from custom implementations other than `LanguageRangeError` propagate.
    func bestMatchForAcceptLanguage(_ acceptLanguage: String?) throws -> String {
        try bestMatchFor(usableAcceptLanguageRanges(acceptLanguage, using: self))
    }
}

/// Shared fail-soft header ingress. Unrelated custom parser errors propagate.
/// Returning no ranges preserves an unmatched diagnostic at the options door.
package func usableAcceptLanguageRanges(_ header: String?, using matcher: any LocaleMatcher) throws -> [LanguageRange] {
    guard let header, header.utf16.count <= DefaultLocaleMatcher.maximumAcceptLanguageCharacters,
          !MatchingLocale.javaTrim(header).isEmpty else { return [] }
    let normalized = MatchingLocale.normalizedAcceptLanguage(header)
    if normalized.isEmpty { return [] }
    let ranges: [LanguageRange]
    do { ranges = try matcher.parseLanguageRanges(normalized) }
    catch is LanguageRangeError { return [] }
    return ranges.count <= DefaultLocaleMatcher.maximumLanguageRanges ? ranges : []
}

/// Invalid locale-matcher configuration or language-range input.
public struct LocaleMatcherError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The category of the failure.
    public enum Kind: String, Sendable {
        /// An `invalidArgument` means the requested input is invalid; `configuration` identifies invalid supported locales, fallback, or tiebreaker settings.
        case invalidArgument, configuration
    }
    /// The category of the failure.
    public let kind: Kind
    /// The diagnostic explanation of the failure.
    public let message: String
    /// The diagnostic message.
    public var description: String { message }

    package init(_ message: String, kind: Kind = .invalidArgument) {
        self.kind = kind
        self.message = message
    }
}
