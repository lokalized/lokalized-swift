/// Locale projection for the JS manifest wire door. Unlike the native matcher
/// constructor, serialized case-distinct known variants remain distinct keys.
package enum ManifestLocale {
    package static func normalizeTag(_ text: String) throws -> String {
        guard !text.isEmpty else { throw LocaleTagError(.malformedLanguageTag, "A locale tag must be a non-empty string") }
        let parts = JDKLocaleTag.parse(text)
        guard parts.wellFormed else { throw LocaleTagError(.malformedLanguageTag, "Locale tag '\(text)' is not a well-formed IETF BCP 47 locale") }
        let projected = JDKLocaleTag.make(parts).tag
        // Manifest-normalization profile 1.1.0 gives private-use-only tags one
        // spelling. Core LocaleTag keeps the pinned JDK carrier behavior.
        return projected.hasPrefix("und-x-") ? String(projected.dropFirst(4)) : projected
    }
    package static func primaryLanguage(_ tag: String) -> String {
        let parts = JDKLocaleTag.parse(tag)
        let language = parts.extlangs.first ?? parts.language
        if language.isEmpty || language == "und" || language == "*" { return "" }
        let canonical = MatchingLocale.canonical(LocaleTag.forLanguageTag(tag).tag)
        let lowered = canonical.lowercased()
        if lowered == "x" || lowered.hasPrefix("x-") { return "" }
        let primary = MatchingLocale.split(canonical).first ?? ""
        return primary.lowercased() == "und" ? "" : primary
    }
    package static func normalizedLanguageCode(_ text: String) -> String {
        let primary = primaryLanguage(text)
        return (primary.isEmpty ? text : primary).lowercased()
    }
    package static func electFallbackLocale(_ configured: String, supported: [String],
        tiebreakerLocalesByLanguageCode: [String: [String]]) -> String? {
        if supported.contains(configured) { return configured }
        let equivalents = supported.filter { MatchingLocale.equivalent($0, configured) }.sorted { ExactString($0) < ExactString($1) }
        if equivalents.count == 1 { return equivalents[0] }
        if equivalents.isEmpty { return nil }
        let key = normalizedLanguageCode(MatchingLocale.split(MatchingLocale.canonical(configured)).first ?? "")
        return resolvedTiebreakers(tiebreakerLocalesByLanguageCode, supported: supported)[key]?.first { equivalents.contains($0) }
    }
    package static func resolvedTiebreakers(_ explicit: [String: [String]], supported: [String]) -> [String: [String]] {
        var resolved: [String: [String]] = [:], groups: [String: [String]] = [:]
        for (key, tags) in explicit {
            let primary = primaryLanguage(key)
            resolved[primary.isEmpty ? key.lowercased() : primary] = tags.map { (try? normalizeTag($0)) ?? $0 }
        }
        for tag in supported {
            let primary = primaryLanguage(tag)
            if !primary.isEmpty { groups[primary, default: []].append(tag) }
        }
        for (primary, tags) in groups where tags.count == 1 && resolved[primary] == nil { resolved[primary] = tags }
        return resolved
    }
}

/// Shares the core candidate-walk rules while retaining serialized manifest keys.
/// The public native matcher keeps its stricter LocaleTag carrier invariants.
package struct ManifestCandidateResolver {
    private let supported: [String]
    private let fallback: String
    private let ties: [String: [String]]
    package init(supported: [String], fallback: String, tiebreakers: [String: [String]]) {
        self.supported = Array(Set(supported)).sorted { ExactString($0) < ExactString($1) }
        self.fallback = fallback
        self.ties = ManifestLocale.resolvedTiebreakers(tiebreakers, supported: self.supported)
    }
    private func preferred(_ range: String, candidates: [String]) -> String? {
        guard let first = candidates.first else { return nil }
        if candidates.count == 1 { return first }
        let primary = ManifestLocale.normalizedLanguageCode(MatchingLocale.split(MatchingLocale.canonical(range)).first ?? "")
        if let tie = ties[primary]?.first(where: { candidates.contains($0) }) { return tie }
        return candidates.contains(fallback) ? fallback : first
    }
    private func likelyMatch(_ tag: String) -> String? {
        guard !CldrLocaleData.hasUndeterminedLanguage(tag), let requested = CldrLocaleData.languageScriptForLikelySubtag(tag) else { return nil }
        let matching = supported.filter {
            !CldrLocaleData.hasUndeterminedLanguage($0) && CldrLocaleData.languageScriptForLikelySubtag($0).map { MatchingLocale.equal($0, requested) } == true
        }
        guard let first = matching.first else { return nil }
        if matching.count == 1 { return first }
        let primary = ManifestLocale.normalizedLanguageCode(MatchingLocale.split(tag).first ?? "")
        if let tie = ties[primary]?.first(where: { matching.contains($0) }) { return tie }
        return matching.contains(fallback) ? fallback : first
    }
    package func chain(_ input: String) throws -> [String] {
        let tag = try ManifestLocale.normalizeTag(input)
        var proposed: [String] = [], seenProposed: Set<String> = []
        func add(_ candidate: String) { if seenProposed.insert(candidate).inserted { proposed.append(candidate) } }
        for candidate in CldrLocaleData.fallbackLocaleTagsFor(tag) { add(candidate) }
        if let likely = likelyMatch(tag) { add(likely) }
        let primary = ManifestLocale.primaryLanguage(tag)
        if !primary.isEmpty {
            for candidate in ties[primary] ?? [] {
                if MatchingLocale.compatible(CldrLocaleData.languageScriptForLikelySubtag(tag), CldrLocaleData.languageScriptForLikelySubtag(candidate)) { add(candidate) }
            }
        }
        add(fallback)
        var result: [String] = [], seen: Set<String> = []
        for candidate in proposed {
            let elected = supported.contains(candidate) ? candidate : preferred(candidate, candidates: supported.filter { MatchingLocale.equivalent($0, candidate) }) ?? candidate
            if seen.insert(elected).inserted { result.append(elected) }
        }
        return result
    }
}
