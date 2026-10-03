public extension DefaultLocaleMatcher {
    func matchFor(_ languageRanges: [LanguageRange]) throws -> LocaleMatchResult {
        try MatchingLocale.requireRangeCount(languageRanges.count)
        func noMatch() throws -> LocaleMatchResult {
            try .init(requestedLanguageRanges: languageRanges, locale: nil, languageRange: nil,
                      effectiveWeight: nil, matchType: .noMatch, fallbackLocale: fallbackTag, consideredLocales: supportedTags)
        }
        if languageRanges.isEmpty { return try noMatch() }
        // With one positive finite preference, an exact loaded tag owns the
        // highest-specificity anchor and the serving walk selects it first.
        // Undetermined non-private ranges have no exact preference semantics.
        // Keep the caller's range and configured tag identity in a fresh,
        // normally validated result; other inputs use the complete election.
        if languageRanges.count == 1, let preference = languageRanges.first,
           preference.weight.isFinite, preference.weight > 0,
           let index = supportedLocales.firstIndex(where: { MatchingLocale.equal($0, preference.range) }),
           !localeStatics[index].undetermined || CldrLocaleData.isPrivateUseLanguageTag(preference.range) {
            return try .init(requestedLanguageRanges: languageRanges, locale: supportedTags[index], languageRange: preference,
                             effectiveWeight: preference.weight, matchType: .exact,
                             fallbackLocale: fallbackTag, consideredLocales: supportedTags)
        }
        // Stable descending Java Double.compare order; request order survives
        // equal weights, while NaN and +/-0 retain the pinned JDK ordering.
        let sortedRanges = languageRanges.enumerated().sorted { first, second in
            let comparison = MatchingLocale.compareWeight(first.element.weight, second.element.weight)
            return comparison == 0 ? first.offset < second.offset : comparison > 0
        }.map(\.element)
        let members = try sortedRanges.map { try MatcherMember($0, equivalents: languageRangeEquivalents) }
        let memberCount = members.count, localeCount = supportedLocales.count
        var representatives = Array(0..<memberCount), active = Array(repeating: false, count: memberCount)
        for index in 0..<memberCount {
            let member = members[index]
            for earlier in 0..<index where representatives[earlier] == earlier {
                let representative = members[earlier]
                if !Set(member.identities).isDisjoint(with: representative.identities) || representative.canonicalIdentity == member.canonicalIdentity {
                    representatives[index] = earlier
                    break
                }
            }
            active[index] = MatchingLocale.compareWeight(member.weight, members[representatives[index]].weight) == 0
        }
        var semanticMembers = Array(0..<memberCount)
        for index in 0..<memberCount where active[index] {
            let representativeIndex = representatives[index], representative = members[representativeIndex]
            if representative.known { continue }
            if !MatchingLocale.equal(representative.range, representative.semanticRange), semanticMembers[representativeIndex] == representativeIndex,
               MatchingLocale.equal(members[index].range, representative.semanticRange) { semanticMembers[representativeIndex] = index }
        }
        func semanticMember(_ index: Int) -> Int { semanticMembers[representatives[index]] }
        var cells: [[MatchSpecificity?]] = []
        for locale in localeStatics {
            var row = Array<MatchSpecificity?>(repeating: nil, count: memberCount)
            for index in 0..<memberCount where active[index] {
                if let cell = specificity(locale, members[index]) {
                    if !cell.isSyntactic && index != semanticMember(index) { continue }
                    row[index] = cell
                }
            }
            cells.append(row)
        }

        var restricted = Set<Int>(), preferredSpecific: [Int: String] = [:]
        var reserved = Array(repeating: false, count: localeCount), ownsAnchor = Array(repeating: false, count: memberCount)
        for localeIndex in 0..<localeCount {
            var best: MatchSpecificity?, bestIndex = -1, bestWeight = -1.0
            for memberIndex in 0..<memberCount {
                guard let cell = cells[localeIndex][memberIndex], cell.isAnchor else { continue }
                if members[memberIndex].weight <= 0 && !cell.excludes { continue }
                if best == nil || cell > best! || (cell == best && members[memberIndex].weight > bestWeight) {
                    best = cell; bestIndex = memberIndex; bestWeight = members[memberIndex].weight
                }
            }
            if bestIndex >= 0 {
                reserved[localeIndex] = true
                let representative = representatives[bestIndex]
                ownsAnchor[representative] = true
                // Owning an anchor also prevents this group spilling into a
                // sibling via likely-script/primary-language inference.
                restricted.insert(representative)
            }
        }
        var assignable: [Int] = []
        for index in 0..<memberCount where representatives[index] == index {
            if members[index].weight <= 0 || members[semanticMembers[index]].recognizedDepth <= 1 { continue }
            restricted.insert(index)
            if !ownsAnchor[index] { assignable.append(index) }
        }
        // Category-major allocation: every likely-script opportunity precedes
        // every primary-language opportunity across the whole preference list.
        for category in [2, 1] {
            let ordered = assignable.sorted { first, second in
                let left = members[semanticMembers[first]], right = members[semanticMembers[second]]
                let leftDepth = category == 2 ? left.recognizedDepth : left.semanticDepth
                let rightDepth = category == 2 ? right.recognizedDepth : right.semanticDepth
                if leftDepth != rightDepth { return leftDepth > rightDepth }
                let comparison = MatchingLocale.compareWeight(left.weight, right.weight)
                return comparison == 0 ? first < second : comparison > 0
            }
            for representative in ordered where preferredSpecific[representative] == nil {
                let semantic = semanticMembers[representative]
                var candidates: [String] = []
                for localeIndex in 0..<localeCount where !reserved[localeIndex] && cells[localeIndex][semantic]?.category == category {
                    candidates.append(supportedLocales[localeIndex])
                }
                let range = members[semantic].semanticRange
                let selected = category == 2 ? likelyMatch(range, candidates: candidates) : preferred(range, candidates: candidates)
                if let selected {
                    preferredSpecific[representative] = selected
                    if let localeIndex = supportedLocales.firstIndex(of: selected) { reserved[localeIndex] = true }
                }
            }
        }

        var governors = Array(repeating: -1, count: localeCount), selectionIndices = Array(repeating: 0, count: localeCount)
        var weights = Array(repeating: 0.0, count: localeCount), highest = 0.0
        for localeIndex in 0..<localeCount {
            let locale = supportedLocales[localeIndex]
            var best: MatchSpecificity?, bestIndex = -1, weight = -1.0
            for memberIndex in 0..<memberCount {
                guard let cell = cells[localeIndex][memberIndex] else { continue }
                let representative = representatives[memberIndex]
                if cell.isHeuristic && restricted.contains(representative) && preferredSpecific[representative] != locale { continue }
                if members[memberIndex].weight <= 0 && !cell.excludes { continue }
                if best == nil || cell > best! || (cell == best && members[memberIndex].weight > weight) {
                    best = cell; bestIndex = memberIndex; weight = members[memberIndex].weight
                }
            }
            if bestIndex < 0 || weight <= 0 { continue }
            let representative = representatives[bestIndex]
            governors[localeIndex] = bestIndex
            weights[localeIndex] = weight
            selectionIndices[localeIndex] = bestIndex == semanticMembers[representative] || !best!.isSyntactic ? representative : bestIndex
            // Java Math.max propagates NaN; Swift max must not silently discard
            // it before LocaleMatchResult's finite-effective-weight validation.
            if weight.isNaN { highest = .nan }
            else if !highest.isNaN && weight > highest { highest = weight }
        }
        if highest <= 0 { return try noMatch() }
        var survivors = Array<[String]?>(repeating: nil, count: memberCount)
        for localeIndex in 0..<localeCount where governors[localeIndex] >= 0 && MatchingLocale.compareWeight(weights[localeIndex], highest) == 0 {
            let index = selectionIndices[localeIndex]
            if survivors[index] == nil { survivors[index] = [] }
            survivors[index]!.append(supportedLocales[localeIndex])
        }
        func result(_ locale: String) throws -> LocaleMatchResult {
            guard let localeIndex = supportedLocales.firstIndex(of: locale), governors[localeIndex] >= 0 else {
                throw LocaleMatcherError("Locale negotiation selected a locale without a governing range")
            }
            let governor = members[governors[localeIndex]]
            return try .init(requestedLanguageRanges: languageRanges, locale: supportedTags[localeIndex], languageRange: governor.preference,
                             effectiveWeight: weights[localeIndex], matchType: matchType(locale, member: governor),
                             fallbackLocale: fallbackTag, consideredLocales: supportedTags)
        }
        for index in 0..<memberCount {
            guard let candidates = survivors[index] else { continue }
            let member = members[index]
            if member.weight <= 0 { continue }
            if member.range == "*" { return try result(preferredWildcard(candidates)) }
            if member.undetermined && !member.privateUse { continue }
            if let exact = candidates.first(where: { MatchingLocale.equal($0, member.range) }) { return try result(exact) }
            for locale in candidates {
                if member.identities.contains(where: { !MatchingLocale.equal($0, member.range) && MatchingLocale.equal(locale, $0) }) {
                    return try result(locale)
                }
            }
            if member.wildcard {
                let filtered = candidates.filter { MatchingLocale.structuralMatch(member.subtags, MatchingLocale.split($0)) }
                if filtered.isEmpty { continue }
                let primary = MatchingLocale.normalizedLanguageCode(MatchingLocale.split(member.range).first ?? "")
                return try result(primary == "*" ? preferredWildcard(filtered) : preferred(member.range, candidates: filtered) ?? filtered[0])
            }
            if member.privateUse { continue }
            let canonical = member.canonicalRange ?? ""
            if let selected = preferred(canonical, candidates: candidates.filter { MatchingLocale.equal(MatchingLocale.canonical($0), canonical) }) { return try result(selected) }
            if let selected = fallbackMatch(member.semanticRange, candidates: candidates) { return try result(selected) }
            if let selected = likelyMatch(member.semanticRange, candidates: candidates) { return try result(selected) }
            let primary = member.primary ?? ""
            var matching = candidates.filter { locale in
                let language = MatchingLocale.primary(locale)
                return !language.isEmpty && MatchingLocale.equal(language, primary)
                    && MatchingLocale.compatible(CldrLocaleData.languageScriptForLikelySubtag(member.semanticRange), CldrLocaleData.languageScriptForLikelySubtag(locale))
            }
            if matching.isEmpty { continue }
            let filtered = matching.filter { MatchingLocale.structuralMatch(member.subtags, MatchingLocale.split($0)) }
            if filtered.contains(where: { !MatchingLocale.equal($0, LocaleTag.forLanguageTag($0).language) }) { matching = filtered }
            if matching.count == 1 { return try result(matching[0]) }
            return try result(tiebreaker(primary, candidates: matching) ?? matching[0])
        }
        return try noMatch()
    }
}
