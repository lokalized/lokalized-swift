/// Immutable diagnostics for one negotiation. Reference identity is retained
/// when a caller supplies a result to a later translation operation.
public final class LocaleMatchResult: Hashable, Sendable {
    public let requestedLanguageRanges: [LanguageRange]
    public let locale: String?
    public let languageRange: LanguageRange?
    public let effectiveWeight: Double?
    public let matchType: LocaleMatchType
    public let fallbackLocale: String
    public let consideredLocales: [String]
    public var isMatch: Bool { locale != nil }
    package let selectedTag: LocaleTag?
    package let fallbackTag: LocaleTag
    package let consideredTags: [LocaleTag]
    public var localeTag: LocaleTag? { selectedTag }
    public var fallbackLocaleTag: LocaleTag { fallbackTag }
    public var consideredLocaleTags: [LocaleTag] { consideredTags }

    public convenience init(requestedLanguageRanges: [LanguageRange], locale: String?, languageRange: LanguageRange?,
                            effectiveWeight: Double?, matchType: LocaleMatchType, fallbackLocale: String,
                            consideredLocales: [String]) throws {
        try self.init(requestedLanguageRanges: requestedLanguageRanges, selectedInput: locale, languageRange: languageRange,
                      effectiveWeight: effectiveWeight, matchType: matchType, fallbackInput: fallbackLocale,
                      consideredInputs: consideredLocales, validate: { try MatchingLocale.validated($0, description: $1) })
    }

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

    public static func == (left: LocaleMatchResult, right: LocaleMatchResult) -> Bool {
        left === right || (left.requestedLanguageRanges == right.requestedLanguageRanges && left.selectedTag == right.selectedTag
            && left.languageRange == right.languageRange && left.effectiveWeight == right.effectiveWeight
            && left.matchType == right.matchType && left.fallbackTag == right.fallbackTag && left.consideredTags == right.consideredTags)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(requestedLanguageRanges); hasher.combine(selectedTag); hasher.combine(languageRange)
        hasher.combine(effectiveWeight); hasher.combine(matchType); hasher.combine(fallbackTag); hasher.combine(consideredTags)
    }
}
