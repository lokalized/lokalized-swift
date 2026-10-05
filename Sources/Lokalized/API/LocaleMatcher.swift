/// Strict locale negotiation and fail-soft HTTP language preference handling.
/// Implementations return diagnostics without manufacturing a fallback match.
public protocol LocaleMatcher: Sendable {
    var fallbackLocale: String { get }
    func matchFor(_ locale: String) throws -> LocaleMatchResult
    func matchFor(_ languageRanges: [LanguageRange]) throws -> LocaleMatchResult
    func bestMatchFor(_ locale: String) throws -> String
    func bestMatchFor(_ languageRanges: [LanguageRange]) throws -> String
    func bestMatchForAcceptLanguage(_ acceptLanguage: String?) throws -> String
    func parseLanguageRanges(_ ranges: String) throws -> [LanguageRange]
}

public extension LocaleMatcher {
    func matchFor(_ locale: String) throws -> LocaleMatchResult {
        let tag = try MatchingLocale.validated(locale, description: "Requested locale").tag
        return try matchFor([LanguageRange(tag)])
    }

    func matchFor(_ locale: LocaleTag) throws -> LocaleMatchResult {
        try JDKLocaleTag.requireWellFormed(locale, description: "Requested locale")
        return try matchFor([LanguageRange(locale.tag)])
    }

    func bestMatchFor(_ locale: String) throws -> String { try matchFor(locale).locale ?? fallbackLocale }
    func bestMatchFor(_ locale: LocaleTag) throws -> String { try matchFor(locale).locale ?? fallbackLocale }
    func bestMatchFor(_ languageRanges: [LanguageRange]) throws -> String { try matchFor(languageRanges).locale ?? fallbackLocale }

    func parseLanguageRanges(_ ranges: String) throws -> [LanguageRange] {
        try LanguageRangeParser.parse(ranges, equivalents: .ianaRegistry)
    }

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
    public enum Kind: String, Sendable { case invalidArgument, configuration }
    public let kind: Kind
    public let message: String
    public var description: String { message }

    package init(_ message: String, kind: Kind = .invalidArgument) {
        self.kind = kind
        self.message = message
    }
}
