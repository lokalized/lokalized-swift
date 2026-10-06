/// Immutable diagnostics for one negotiation. Reference identity is retained
/// when a caller supplies a result to a later translation operation.
public final class LocaleMatchResult: Hashable, Sendable {
    /// The original preferences supplied to the negotiation, in caller order.
    public let requestedLanguageRanges: [LanguageRange]
    /// The selected supported locale tag, or `nil` when no preference matched.
    public let locale: String?
    /// The requested preference responsible for the match, or `nil` when unmatched.
    public let languageRange: LanguageRange?
    /// The winning preference weight, or `nil` when unmatched.
    public let effectiveWeight: Double?
    /// How the selected locale matched the request; `.noMatch` when no locale was selected.
    public let matchType: LocaleMatchType
    /// The normalized configured fallback locale, available even when the result is unmatched.
    public let fallbackLocale: String
    /// The normalized supported locale tags considered by the matcher.
    public let consideredLocales: [String]
    /// Whether negotiation selected a locale. The configured fallback alone does not count as a match.
    public var isMatch: Bool { locale != nil }
    package let selectedTag: LocaleTag?
    package let fallbackTag: LocaleTag
    package let consideredTags: [LocaleTag]
    /// The selected locale as a typed value, or `nil` when unmatched.
    public var localeTag: LocaleTag? { selectedTag }
    /// The configured fallback as a typed value.
    public var fallbackLocaleTag: LocaleTag { fallbackTag }
    /// The considered locales as typed values, in the same order as `consideredLocales`.
    public var consideredLocaleTags: [LocaleTag] { consideredTags }

    /// Creates immutable negotiation diagnostics and validates their consistency.
    ///
    /// A matched result requires a selected considered locale, a requested range, a finite positive weight, and a non-`.noMatch` type.
    /// An unmatched result omits the selected locale, range, and weight. Considered locales must be unique and contain the fallback.
    /// Throws `LocaleMatcherError` for inconsistent results or invalid locale inputs.
    public convenience init(requestedLanguageRanges: [LanguageRange], locale: String?, languageRange: LanguageRange?,
                            effectiveWeight: Double?, matchType: LocaleMatchType, fallbackLocale: String,
                            consideredLocales: [String]) throws {
        try self.init(requestedLanguageRanges: requestedLanguageRanges, selectedInput: locale, languageRange: languageRange,
                      effectiveWeight: effectiveWeight, matchType: matchType, fallbackInput: fallbackLocale,
                      consideredInputs: consideredLocales, validate: { try MatchingLocale.validated($0, description: $1) })
    }

    /// Creates immutable negotiation diagnostics and validates their consistency.
    ///
    /// A matched result requires a selected considered locale, a requested range, a finite positive weight, and a non-`.noMatch` type.
    /// An unmatched result omits the selected locale, range, and weight. Considered locales must be unique and contain the fallback.
    /// Throws `LocaleMatcherError` for inconsistent results or invalid locale inputs.
    public convenience init(requestedLanguageRanges: [LanguageRange], locale: LocaleTag?, languageRange: LanguageRange?,
                            effectiveWeight: Double?, matchType: LocaleMatchType, fallbackLocale: LocaleTag,
                            consideredLocales: [LocaleTag]) throws {
        try self.init(requestedLanguageRanges: requestedLanguageRanges, selectedInput: locale, languageRange: languageRange,
                      effectiveWeight: effectiveWeight, matchType: matchType, fallbackInput: fallbackLocale,
                      consideredInputs: consideredLocales, validate: { try JDKLocaleTag.requireWellFormed($0, description: $1) })
    }

    private init<Input>(requestedLanguageRanges: [LanguageRange], selectedInput: Input?, languageRange: LanguageRange?,
                        effectiveWeight: Double?, matchType: LocaleMatchType, fallbackInput: Input,
                        consideredInputs: [Input], validate: (Input, String) throws -> LocaleTag) throws {
        try MatchingLocale.requireRangeCount(requestedLanguageRanges.count)
        self.requestedLanguageRanges = requestedLanguageRanges
        selectedTag = try selectedInput.map { try validate($0, "Selected locale") }
        self.locale = selectedTag?.tag
        self.languageRange = languageRange
        self.effectiveWeight = effectiveWeight
        self.matchType = matchType
        fallbackTag = try validate(fallbackInput, "Fallback locale")
        self.fallbackLocale = fallbackTag.tag
        if selectedInput == nil && (languageRange != nil || effectiveWeight != nil || matchType != .noMatch) {
            throw LocaleMatcherError("An unmatched locale result must use NONE and omit range and weight")
        }
        if selectedInput != nil && (languageRange == nil || effectiveWeight == nil || matchType == .noMatch) {
            throw LocaleMatcherError("A matched locale result requires a range, weight, and non-NONE match type")
        }
        if let languageRange, !requestedLanguageRanges.contains(languageRange) {
            throw LocaleMatcherError("The matched language range must be present in requested language ranges")
        }
        if let effectiveWeight, !effectiveWeight.isFinite || effectiveWeight <= 0 || effectiveWeight > 1 {
            throw LocaleMatcherError("A matched locale result requires a finite effective weight greater than 0 and at most 1")
        }
        var tags: [LocaleTag] = [], seen = Set<String>()
        for supplied in consideredInputs {
            let tag = try validate(supplied, "Considered locale")
            guard seen.insert(tag.tag.lowercased()).inserted else {
                throw LocaleMatcherError("Considered locales must not contain duplicate language tag '\(tag.tag)'")
            }
            tags.append(tag)
        }
        guard Set(tags).count == tags.count else { throw LocaleMatcherError("Considered locales must not contain duplicates") }
        guard tags.contains(fallbackTag) else { throw LocaleMatcherError("The fallback locale must be present in considered locales") }
        if let selectedTag, !tags.contains(selectedTag) { throw LocaleMatcherError("The selected locale must be present in considered locales") }
        consideredTags = tags
        self.consideredLocales = tags.map(\.tag)
    }

    /// Compares the stored values for equality, preserving exact catalog-text spelling where applicable.
    public static func == (left: LocaleMatchResult, right: LocaleMatchResult) -> Bool {
        left === right || (left.requestedLanguageRanges == right.requestedLanguageRanges && left.selectedTag == right.selectedTag
            && left.languageRange == right.languageRange && left.effectiveWeight == right.effectiveWeight
            && left.matchType == right.matchType && left.fallbackTag == right.fallbackTag && left.consideredTags == right.consideredTags)
    }

    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(requestedLanguageRanges); hasher.combine(selectedTag); hasher.combine(languageRange)
        hasher.combine(effectiveWeight); hasher.combine(matchType); hasher.combine(fallbackTag); hasher.combine(consideredTags)
    }
}
