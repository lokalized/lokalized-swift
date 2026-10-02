/// Immutable negotiation configuration backed by pinned JDK/IANA/CLDR tables.
/// No Foundation.Locale or host ICU negotiation participates in matching.
public struct DefaultLocaleMatcher: LocaleMatcher, Sendable {
    public static let maximumLanguageRanges = 32
    public static let maximumAcceptLanguageCharacters = 4_096
    public let supportedLocales: [String]
    public let fallbackLocale: String
    public let tiebreakerLocalesByLanguageCode: [String: [String]]
    public let languageRangeEquivalents: LanguageRangeEquivalents
    package let supportedTags: [LocaleTag]
    package let fallbackTag: LocaleTag
    package let localeStatics: [MatcherLocale]
    public var supportedLocaleTags: [LocaleTag] { supportedTags }
    public var fallbackLocaleTag: LocaleTag { fallbackTag }
    public let tiebreakerLocaleTagsByLanguageCode: [String: [LocaleTag]]

    public init(supportedLocales: [String], fallbackLocale: String,
                tiebreakerLocalesByLanguageCode: [String: [String]] = [:],
                languageRangeEquivalents: LanguageRangeEquivalents = .ianaRegistry) throws {
        try self.init(inputs: supportedLocales, fallbackInput: fallbackLocale,
                      tiebreakerInputs: tiebreakerLocalesByLanguageCode,
                      languageRangeEquivalents: languageRangeEquivalents,
                      validate: { try MatchingLocale.validated($0, description: $1) })
    }

    public init(supportedLocales: [LocaleTag], fallbackLocale: LocaleTag,
                tiebreakerLocalesByLanguageCode: [String: [LocaleTag]] = [:],
                languageRangeEquivalents: LanguageRangeEquivalents = .ianaRegistry) throws {
        try self.init(inputs: supportedLocales, fallbackInput: fallbackLocale,
                      tiebreakerInputs: tiebreakerLocalesByLanguageCode,
                      languageRangeEquivalents: languageRangeEquivalents,
                      validate: { try JDKLocaleTag.requireWellFormed($0, description: $1) })
    }

    private init<Input>(inputs: [Input], fallbackInput: Input,
                        tiebreakerInputs: [String: [Input]],
                        languageRangeEquivalents: LanguageRangeEquivalents,
                        validate: (Input, String) throws -> LocaleTag) throws {
        let requestedFallback = try validate(fallbackInput, "Fallback locale")
        var loaded: [LocaleTag] = [], seen: [String: LocaleTag] = [:]
        for supplied in inputs {
            let tag = try validate(supplied, "Localized strings locale")
            if let existing = seen.updateValue(tag, forKey: tag.tag.lowercased()) {
                throw LocaleMatcherError("Localized strings locales '\(existing.javaIdentifier)' and '\(tag.javaIdentifier)' both use IETF BCP 47 language tag '\(tag.tag)'", kind: .configuration)
            }
            loaded.append(tag)
        }
        loaded.sort { $0.tag < $1.tag }
        let equivalents = loaded.filter { MatchingLocale.equivalent($0.tag, requestedFallback.tag) }
        guard !equivalents.isEmpty else {
            throw LocaleMatcherError("Specified fallback locale is '\(requestedFallback.tag)' but no matching localized strings locale was found. Known locales: \(Self.list(loaded.map(\.tag)))", kind: .configuration)
        }
        var resolved: [String: [LocaleTag]] = [:], suppliedKeys: [String: String] = [:]
        // Swift dictionaries have no caller insertion order. Deterministic key
        // order chooses the first invalid configuration when several are wrong.
        for suppliedCode in tiebreakerInputs.keys.sorted() {
            let code = try Self.normalizedTiebreakerCode(suppliedCode)
            if let existing = suppliedKeys[code] {
                throw LocaleMatcherError("Tiebreaker language codes '\(existing)' and '\(suppliedCode)' both normalize to '\(code)'", kind: .configuration)
            }
            suppliedKeys[code] = suppliedCode
            var tags: [LocaleTag] = [], unique = Set<LocaleTag>()
            for supplied in tiebreakerInputs[suppliedCode]! {
                let tag = try validate(supplied, "Tiebreaker locale")
                guard unique.insert(tag).inserted else {
                    throw LocaleMatcherError("Duplicate tiebreaker locale '\(tag.tag)' encountered for language code '\(suppliedCode)'", kind: .configuration)
                }
                tags.append(tag)
            }
            resolved[code] = tags
        }
        var byLanguage: [String: [LocaleTag]] = [:]
        for tag in loaded {
            let primary = MatchingLocale.primary(tag.tag)
            if !primary.isEmpty { byLanguage[primary, default: []].append(tag) }
        }
        for code in resolved.keys.sorted() {
            guard let supported = byLanguage[code] else {
                throw LocaleMatcherError("Tiebreaker language code '\(code)' has no localized strings locales", kind: .configuration)
            }
            let supplied = resolved[code]!, provided = Set(supplied)
            if provided != Set(supported) {
                let missing = supported.filter { !provided.contains($0) }
                let unrelated = supplied.filter { !supported.contains($0) }.sorted { $0.tag < $1.tag }
                throw LocaleMatcherError("Tiebreaker locales for language code '\(code)' must be an exact permutation of loaded locales \(Self.list(supported.map(\.tag))); missing: \(Self.list(missing.map(\.tag))); unrelated: \(Self.list(unrelated.map(\.tag)))", kind: .configuration)
            }
        }
        for code in byLanguage.keys.sorted() {
            let tags = byLanguage[code]!
            if tags.count == 1 && resolved[code] == nil { resolved[code] = tags }
            else if tags.count > 1 && resolved[code] == nil {
                throw LocaleMatcherError("You must specify tiebreaker locales via 'tiebreakerLocalesByLanguageCode' to resolve ambiguity for language code '\(code)' because localized strings exist for the following locale[s]: \(Self.list(tags.map(\.tag)))", kind: .configuration)
            }
        }
        let elected: LocaleTag?
        if let exact = loaded.first(where: { $0 == requestedFallback }) { elected = exact }
        else if equivalents.count == 1 { elected = equivalents[0] }
        else {
            let language = MatchingLocale.normalizedLanguageCode(MatchingLocale.split(MatchingLocale.canonical(requestedFallback.tag)).first ?? "")
            let ordered = resolved[language] ?? []
            elected = ordered.first { equivalents.contains($0) }
        }
        guard let elected else {
            throw LocaleMatcherError("Fallback locale '\(requestedFallback.tag)' is canonically equivalent to multiple loaded locales \(Self.list(equivalents.map(\.tag))); configure tiebreakerLocalesByLanguageCode to choose one", kind: .configuration)
        }
        supportedTags = loaded
        self.supportedLocales = loaded.map(\.tag)
        fallbackTag = elected
        self.fallbackLocale = elected.tag
        self.tiebreakerLocalesByLanguageCode = resolved.mapValues { $0.map(\.tag) }
        self.tiebreakerLocaleTagsByLanguageCode = resolved
        self.languageRangeEquivalents = languageRangeEquivalents
        localeStatics = loaded.map { MatcherLocale($0.tag) }
    }

    public func parseLanguageRanges(_ ranges: String) throws -> [LanguageRange] {
        try LanguageRangeParser.parse(ranges, equivalents: languageRangeEquivalents)
    }

    /// Applies contextual checks after the result's constructor invariants.
    /// Caller considered-locale order is retained; only the set is compared.
    public func validateSuppliedMatch(_ result: LocaleMatchResult) throws -> LocaleMatchResult {
        guard result.fallbackTag == fallbackTag else {
            throw LocaleMatcherError("localeMatchSupplier returned a result for a different fallback locale")
        }
        guard Set(result.consideredTags) == Set(supportedTags) else {
            throw LocaleMatcherError("localeMatchSupplier returned a result for different supported locales")
        }
        return result
    }

    private static func normalizedTiebreakerCode(_ supplied: String) throws -> String {
        if !supplied.isEmpty && (!(2...8).contains(supplied.utf8.count) || !supplied.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) })) {
            throw LocaleMatcherError("Tiebreaker language code '\(supplied)' must be a well-formed primary language subtag", kind: .configuration)
        }
        let primary = MatchingLocale.primary(supplied)
        guard !primary.isEmpty else {
            throw LocaleMatcherError("Tiebreaker language code '\(supplied)' must identify a primary language", kind: .configuration)
        }
        return primary
    }
    private static func list(_ tags: [String]) -> String { "[" + tags.joined(separator: ", ") + "]" }

    package func preferred(_ range: String, candidates: [String]) -> String? {
        if candidates.isEmpty { return nil }
        if candidates.count == 1 { return candidates[0] }
        let primary = MatchingLocale.normalizedLanguageCode(MatchingLocale.split(MatchingLocale.canonical(range)).first ?? "")
        if let tiebreaker = tiebreaker(primary, candidates: candidates) { return tiebreaker }
        if candidates.contains(fallbackLocale) { return fallbackLocale }
        return candidates[0]
    }
    package func tiebreaker(_ primary: String, candidates: [String]) -> String? {
        tiebreakerLocalesByLanguageCode[primary]?.first { candidates.contains($0) }
    }
    package func preferredWildcard(_ candidates: [String]) -> String {
        precondition(!candidates.isEmpty)
        if candidates.contains(fallbackLocale) { return fallbackLocale }
        let primary = MatchingLocale.primary(fallbackLocale)
        if !primary.isEmpty, let tie = tiebreaker(primary, candidates: candidates) { return tie }
        return candidates[0]
    }
    package func likelyMatch(_ range: String, candidates: [String]) -> String? {
        guard !range.contains("*"), !CldrLocaleData.hasUndeterminedLanguage(range),
              let requested = CldrLocaleData.languageScriptForLikelySubtag(range) else { return nil }
        let matching = candidates.filter { tag in
            !CldrLocaleData.hasUndeterminedLanguage(tag)
                && CldrLocaleData.languageScriptForLikelySubtag(tag).map { MatchingLocale.equal($0, requested) } == true
        }
        if matching.isEmpty { return nil }
        if matching.count == 1 { return matching[0] }
        let primary = MatchingLocale.normalizedLanguageCode(MatchingLocale.split(range).first ?? "")
        if let tie = tiebreaker(primary, candidates: matching) { return tie }
        return matching.contains(fallbackLocale) ? fallbackLocale : matching[0]
    }
    package func fallbackMatch(_ range: String, candidates: [String]) -> String? {
        if range.contains("*") { return nil }
        let chain = CldrLocaleData.fallbackLocaleTagsFor(LocaleTag.forLanguageTag(range).tag)
        for parent in chain {
            if let exact = candidates.first(where: { MatchingLocale.equal($0, parent) }) { return exact }
        }
        for parent in chain {
            if let equivalent = preferred(parent, candidates: candidates.filter { MatchingLocale.equivalent($0, parent) }) { return equivalent }
        }
        return nil
    }

    /// The later per-key resolution walk is deliberately separate from matchFor.
    /// Unloaded ancestors remain observable; canonical rewrites deduplicate after
    /// election, and the configured fallback is always the last added candidate.
    package func candidateChain(for locale: String) throws -> [String] {
        let tag = try MatchingLocale.validated(locale, description: "Requested locale").tag
        var proposed: [String] = [], seenProposed = Set<String>()
        func add(_ candidate: String) { if seenProposed.insert(candidate).inserted { proposed.append(candidate) } }
        for candidate in CldrLocaleData.fallbackLocaleTagsFor(tag) { add(candidate) }
        if let likely = likelyMatch(tag, candidates: supportedLocales) { add(likely) }
        let primary = MatchingLocale.primary(tag)
        if !primary.isEmpty {
            for tie in tiebreakerLocalesByLanguageCode[primary] ?? [] {
                if MatchingLocale.compatible(CldrLocaleData.languageScriptForLikelySubtag(tag), CldrLocaleData.languageScriptForLikelySubtag(tie)) { add(tie) }
            }
        }
        add(fallbackLocale)
        var chain: [String] = [], seen = Set<String>()
        for candidate in proposed {
            let attempted = supportedLocales.contains(candidate) ? candidate
                : preferred(candidate, candidates: supportedLocales.filter { MatchingLocale.equivalent($0, candidate) }) ?? candidate
            if seen.insert(attempted).inserted { chain.append(attempted) }
        }
        return chain
    }
}
