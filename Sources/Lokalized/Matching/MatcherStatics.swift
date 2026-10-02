package struct MatchSpecificity: Comparable, Sendable {
    package let category: Int
    package let depth: Int
    package let distance: Int
    package var isAnchor: Bool { category > 2 }
    package var isHeuristic: Bool { category == 1 || category == 2 }
    package var isSyntactic: Bool { category == 6 || category == 4 }
    package var excludes: Bool { category == 6 || category == 5 || category == 4 }
    package static func < (first: Self, second: Self) -> Bool {
        if first.category != second.category { return first.category < second.category }
        if first.depth != second.depth { return first.depth < second.depth }
        return first.distance > second.distance
    }
}

package struct MatcherLocale: Sendable {
    package let tag: String
    package let subtags: [String]
    package let canonical: String
    package let canonicalSubtags: [String]
    package let undetermined: Bool
    package let likelyLanguageScript: String?
    package let primary: String?
    package init(_ tag: String) {
        self.tag = tag
        subtags = MatchingLocale.split(tag)
        canonical = MatchingLocale.canonical(tag)
        canonicalSubtags = MatchingLocale.split(canonical)
        undetermined = CldrLocaleData.hasUndeterminedLanguage(tag)
        likelyLanguageScript = CldrLocaleData.languageScriptForLikelySubtag(tag)
        let language = MatchingLocale.primary(tag)
        primary = language.isEmpty ? nil : language
    }
}

package struct MatcherMember: Sendable {
    package let preference: LanguageRange
    package var range: String { preference.range }
    package var weight: Double { preference.weight }
    package let identities: [String]
    package let known: Bool
    package let semanticRange: String
    package let canonicalIdentity: String
    package let structuralRange: String
    package let subtags: [String]
    package let structuralDepth: Int
    package let privateUse: Bool
    package let undetermined: Bool
    package let wildcard: Bool
    package let bareWildcard: Bool
    package let recognizedDepth: Int
    package let semanticDepth: Int
    package let canonicalRange: String?
    package let canonicalSubtags: [String]?
    package let fallbackCanonicalTags: [String]?
    package let likelyLanguageScript: String?
    package let primary: String?

    package init(_ preference: LanguageRange, equivalents: LanguageRangeEquivalents) throws {
        self.preference = preference
        let range = preference.range
        wildcard = range.contains("*")
        structuralRange = MatchingLocale.normalizedExtended(range)
        privateUse = CldrLocaleData.isPrivateUseLanguageTag(range)
        undetermined = CldrLocaleData.hasUndeterminedLanguage(range)
        known = CldrLocaleData.isKnownLanguageTag(range)
        identities = try Self.identities(range, equivalents: equivalents)
        semanticRange = Self.semantic(range, known: known, wildcard: wildcard, identities: identities)
        canonicalIdentity = Self.canonicalIdentity(semanticRange)
        subtags = MatchingLocale.split(range)
        structuralDepth = MatchingLocale.structuralDepth(structuralRange)
        bareWildcard = structuralRange == "*"
        recognizedDepth = Self.recognizedDepth(semanticRange)
        if !wildcard && !undetermined && !privateUse {
            semanticDepth = MatchingLocale.structuralDepth(MatchingLocale.normalizedExtended(semanticRange))
            canonicalRange = MatchingLocale.canonical(semanticRange)
            canonicalSubtags = canonicalRange.map(MatchingLocale.split)
            fallbackCanonicalTags = CldrLocaleData.fallbackLocaleTagsFor(LocaleTag.forLanguageTag(semanticRange).tag).map(MatchingLocale.canonical)
            likelyLanguageScript = CldrLocaleData.languageScriptForLikelySubtag(semanticRange)
            primary = MatchingLocale.normalizedLanguageCode(MatchingLocale.split(semanticRange).first ?? "")
        } else {
            semanticDepth = 0; canonicalRange = nil; canonicalSubtags = nil; fallbackCanonicalTags = nil
            likelyLanguageScript = nil; primary = nil
        }
    }

    private static func canonicalIdentity(_ range: String) -> String {
        (range.contains("*") ? range : MatchingLocale.canonical(range)).lowercased()
    }
    private static func identities(_ range: String, equivalents: LanguageRangeEquivalents) throws -> [String] {
        var identities: [String] = [], seen = Set<String>()
        func add(_ text: String) { let lower = text.lowercased(); if seen.insert(lower).inserted { identities.append(lower) } }
        func addParsed(_ text: String) throws {
            for parsed in try LanguageRangeParser.parse(text, equivalents: equivalents) { add(parsed.range) }
        }
        add(range)
        try addParsed(range)
        if let extlang = extlangEquivalent(range) { add(extlang); try addParsed(extlang) }
        return identities
    }
    private static func extlangEquivalent(_ range: String) -> String? {
        if range.contains("*") { return nil }
        let parts = MatchingLocale.split(range)
        func alphabetic(_ part: String) -> Bool { !part.isEmpty && part.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) } }
        guard parts.count >= 2, (parts[0].utf8.count == 2 || parts[0].utf8.count == 3), alphabetic(parts[0]),
              parts[1].utf8.count == 3, alphabetic(parts[1]) else { return nil }
        let candidate = parts.dropFirst().joined(separator: "-").lowercased()
        guard CldrLocaleData.isKnownLanguageTag(candidate), MatchingLocale.equal(LocaleTag.forLanguageTag(range).tag, candidate) else { return nil }
        return candidate
    }
    private static func recognizedDepth(_ range: String) -> Int {
        guard CldrLocaleData.isKnownLanguageTag(range) else { return 1 }
        let canonical = LocaleTag.forLanguageTag(MatchingLocale.canonical(range))
        return max(1, (canonical.language.isEmpty ? 0 : 1) + (canonical.script.isEmpty ? 0 : 1) + (canonical.region.isEmpty ? 0 : 1))
    }
    private static func semantic(_ range: String, known: Bool, wildcard: Bool, identities: [String]) -> String {
        if known || wildcard { return range }
        let jdkTag = LocaleTag.forLanguageTag(range).tag
        var selected = range, jdkSemantic = MatchingLocale.equal(range, jdkTag), knownTag = false, constraints = 1
        var stable = canonicalIdentity(range) == range.lowercased()
        for candidate in identities {
            let nextJDK = MatchingLocale.equal(candidate, jdkTag), nextKnown = CldrLocaleData.isKnownLanguageTag(candidate)
            let nextConstraints = recognizedDepth(candidate), nextStable = canonicalIdentity(candidate) == candidate.lowercased()
            if (nextJDK && !jdkSemantic) || (nextJDK == jdkSemantic &&
                ((nextKnown && !knownTag) || (nextKnown == knownTag &&
                 (nextConstraints > constraints || (nextConstraints == constraints && nextStable && !stable))))) {
                selected = candidate; jdkSemantic = nextJDK; knownTag = nextKnown; constraints = nextConstraints; stable = nextStable
            }
        }
        return selected
    }
}

package extension DefaultLocaleMatcher {
    func specificity(_ locale: MatcherLocale, _ member: MatcherMember) -> MatchSpecificity? {
        func relation(_ category: Int, _ depth: Int, _ distance: Int = 0) -> MatchSpecificity { .init(category: category, depth: depth, distance: distance) }
        if member.bareWildcard { return relation(0, 0) }
        if member.undetermined && !member.privateUse { return nil }
        let broadStructural = member.weight > 0 && !member.wildcard && member.structuralDepth == 1
        if MatchingLocale.equal(locale.tag, member.structuralRange) { return relation(6, member.structuralDepth) }
        if member.privateUse && !member.wildcard { return nil }
        if MatchingLocale.structuralMatch(member.subtags, locale.subtags) && !broadStructural { return relation(4, member.structuralDepth) }
        if member.wildcard { return nil }
        for identity in member.identities where !MatchingLocale.equal(identity, member.range) && MatchingLocale.equal(locale.tag, identity) {
            return relation(5, MatchingLocale.structuralDepth(identity))
        }
        let broadSemantic = member.weight > 0 && member.semanticDepth == 1
        let canonical = member.canonicalRange ?? ""
        if MatchingLocale.equal(locale.canonical, canonical) { return relation(5, member.semanticDepth) }
        if MatchingLocale.structuralMatch(member.canonicalSubtags ?? [], locale.canonicalSubtags) && !broadSemantic {
            return relation(5, member.semanticDepth)
        }
        for (distance, tag) in (member.fallbackCanonicalTags ?? []).enumerated() where MatchingLocale.equal(locale.canonical, tag) {
            return relation(3, member.semanticDepth, distance)
        }
        let availableScript = locale.undetermined ? nil : locale.likelyLanguageScript
        if let requested = member.likelyLanguageScript, let available = availableScript, MatchingLocale.equal(requested, available) {
            return relation(2, member.recognizedDepth)
        }
        if let primary = locale.primary, let requested = member.primary, MatchingLocale.equal(primary, requested),
           MatchingLocale.compatible(member.likelyLanguageScript, locale.likelyLanguageScript) {
            return relation(1, member.semanticDepth)
        }
        return nil
    }

    func matchType(_ locale: String, member: MatcherMember) -> LocaleMatchType {
        if member.range == "*" { return .wildcard }
        if MatchingLocale.equal(locale, member.range) { return .exact }
        if member.wildcard { return .extendedRange }
        for identity in member.identities where !MatchingLocale.equal(identity, member.range) && MatchingLocale.equal(locale, identity) { return .canonical }
        if MatchingLocale.equal(MatchingLocale.canonical(locale), MatchingLocale.canonical(member.semanticRange)) { return .canonical }
        if fallbackMatch(member.semanticRange, candidates: [locale]) != nil { return .cldrFallback }
        if likelyMatch(member.semanticRange, candidates: [locale]) != nil { return .likelySubtag }
        if MatchingLocale.structuralMatch(member.subtags, MatchingLocale.split(locale)) { return .extendedRange }
        return .primaryLanguage
    }
}
