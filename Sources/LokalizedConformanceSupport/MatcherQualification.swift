import Lokalized

public extension ConformanceRunner {
    /// Native matcher checks shared by XCTest and the standalone runner. These
    /// include measured Java witnesses absent from the shared behavioral corpus.
    static func matcherSelfTest() throws -> Int {
        var checks = 0
        func expect(_ condition: Bool, _ detail: String) throws {
            guard condition else { throw ConformanceError("Matcher self-test failed: \(detail)") }
            checks += 1
        }
        func refusal(_ expected: String, _ action: () throws -> Void) throws {
            var message: String?
            do { try action() } catch { message = String(describing: error) }
            try expect(message == expected, "expected '\(expected)', received '\(message ?? "no refusal")'")
        }
        func probeFailure(_ expected: MatcherProbeError, _ action: () throws -> Void) throws {
            var observed: MatcherProbeError?
            do { try action() } catch { observed = error as? MatcherProbeError }
            try expect(observed == expected, "custom matcher error \(expected) must propagate")
        }
        let simple = try DefaultLocaleMatcher(supportedLocales: ["fr", "EN"], fallbackLocale: "en")
        let equalWeight = [try LanguageRange("fr", weight: 0.7), try LanguageRange("en", weight: 0.7)]
        let chosen = try simple.matchFor(equalWeight)
        try expect(chosen.locale == "fr" && chosen.matchType == .exact && chosen.effectiveWeight == 0.7, "stable equal-quality request order")
        try expect(chosen.requestedLanguageRanges == equalWeight && chosen.languageRange == equalWeight[0], "requested and governing weighted range are retained")
        try expect(chosen.consideredLocales == ["en", "fr"], "considered locales sort by Java tag order")
        try expect(try simple.matchFor(Array(equalWeight.reversed())).locale == "en", "reversed equal-quality order is observable")
        let empty = try simple.matchFor([])
        try expect(!empty.isMatch && empty.locale == nil && empty.languageRange == nil && empty.effectiveWeight == nil && empty.matchType == .noMatch, "strict empty request has no manufactured fallback match")
        try expect(try simple.bestMatchFor([]) == "en", "bestMatch returns fallback for an unmatched request")
        try expect(try simple.matchFor(LocaleTag("fr")).locale == "fr", "typed locale ingress")

        // Single exact preferences retain quality, typed identities and fresh
        // result objects, including aliases, unknown tags and private use.
        let exactTags = [try LocaleTag("en-US"), try LocaleTag("mo"), try LocaleTag("qaa"),
                         try LocaleTag("x-a"), try LocaleTag("en-US-u-nu-latn"),
                         LocaleTag.forLanguageTag("no-NO-x-lvariant-NY")]
        for mode in [LanguageRangeEquivalents.ianaRegistry, .jdk] {
            for tag in exactTags {
                let matcher = try DefaultLocaleMatcher(supportedLocales: [tag], fallbackLocale: tag, languageRangeEquivalents: mode)
                let preference = try LanguageRange(tag.tag.uppercased(), weight: Double.leastNonzeroMagnitude)
                let result = try matcher.matchFor([preference])
                try expect(result.localeTag == tag && result.fallbackLocaleTag == tag && result.consideredLocaleTags == [tag]
                           && result.matchType == .exact && result.effectiveWeight?.bitPattern == preference.weight.bitPattern
                           && result.languageRange == preference && result.requestedLanguageRanges == [preference],
                           "single exact preference preserves every field: \(mode), \(tag.tag)")
                let repeated = try matcher.matchFor([preference])
                try expect(repeated == result && repeated !== result, "single exact result is fresh: \(mode), \(tag.tag)")
            }
        }
        try refusal("A matched locale result requires a finite effective weight greater than 0 and at most 1") {
            _ = try simple.matchFor([LanguageRange("fr", weight: .nan)])
        }
        for zero in [0.0, -0.0] {
            let excluded = try simple.matchFor([LanguageRange("fr", weight: zero)])
            try expect(excluded.matchType == .noMatch && excluded.locale == nil
                       && excluded.requestedLanguageRanges[0].weight.bitPattern == zero.bitPattern,
                       "single exact signed-zero preference remains excluded")
        }

        let signed = try DefaultLocaleMatcher(supportedLocales: ["en", "nsl"], fallbackLocale: "en")
        let localeIngress = try signed.matchFor("sgn-nsl")
        let rangeIngress = try signed.matchFor([LanguageRange("sgn-nsl")])
        try expect(localeIngress.locale == "nsl" && localeIngress.languageRange?.range == "nsl" && localeIngress.matchType == .exact, "locale ingress performs JDK projection")
        try expect(rangeIngress.locale == "nsl" && rangeIngress.languageRange?.range == "sgn-nsl" && rangeIngress.matchType == .canonical, "range ingress preserves raw spelling")
        try refusal("Requested locale 'de-*' is not a well-formed IETF BCP 47 locale") { _ = try simple.matchFor("de-*") }
        try expect(try simple.matchFor([LanguageRange("de-*")]).matchType == .noMatch, "wildcard is legal range syntax")

        let script = try DefaultLocaleMatcher(supportedLocales: ["en-Latn-US", "fr"], fallbackLocale: "fr")
        try expect(try script.matchFor([LanguageRange("en-latn")]).matchType == .likelySubtag, "wildcard-free structural relationship rederives public likely-subtag type")
        try expect(try script.matchFor([LanguageRange("en-*-us")]).matchType == .extendedRange, "actual extended range reports extended-range")
        try expect(try script.matchFor([LanguageRange("en-*-gb")]).matchType == .noMatch, "extended ranges never broaden semantically")

        // JS's independent tests record these witnesses against the Java oracle.
        let anchors = try DefaultLocaleMatcher(supportedLocales: ["cmn-Hans", "en", "zh"], fallbackLocale: "en",
                                               tiebreakerLocalesByLanguageCode: ["zh": ["zh", "cmn-Hans"]])
        let anchored = try anchors.matchFor([LanguageRange("cmn"), LanguageRange("zh")])
        try expect(anchored.locale == "zh" && anchored.matchType == .exact && anchored.languageRange?.range == "zh", "anchor owner cannot spill into likely-script sibling")
        try expect(try anchors.matchFor([LanguageRange("cmn")]).matchType == .canonical, "single-member anchor control")
        let governors = try DefaultLocaleMatcher(supportedLocales: ["en", "nsi-Latn-DE", "nsl"], fallbackLocale: "en")
        let governed = try governors.matchFor([LanguageRange("sgn-no"), LanguageRange("nsl")])
        try expect(governed.locale == "nsi-Latn-DE" && governed.matchType == .likelySubtag && governed.languageRange?.range == "sgn-no", "syntactic nonsemantic governor selects at own member position")
        try expect(try governors.matchFor([LanguageRange("nsl")]).locale == "nsl", "single-member syntactic control")
        let norwegian = try DefaultLocaleMatcher(supportedLocales: ["en", "nb", "no"], fallbackLocale: "nb")
        let norwegianMatch = try norwegian.matchFor([LanguageRange("no-bok"), LanguageRange("nb")])
        try expect(norwegianMatch.locale == "no" && norwegianMatch.matchType == .cldrFallback && norwegianMatch.languageRange?.range == "no-bok", "compound alias semantic group preserves serving position")

        for (requested, loaded) in [("mgp-BU", "mrd-MM"), ("mrh-BU", "shl-MM"), ("yol-heploc", "enm-alalc97"), ("nsl-heploc", "sgn-NO-alalc97")] {
            let matcher = try DefaultLocaleMatcher(supportedLocales: ["en", loaded], fallbackLocale: "en")
            let result = try matcher.matchFor(requested)
            try expect(result.locale == LocaleTag.forLanguageTag(loaded).tag && result.matchType == .canonical, "composed IANA language plus region/variant identity: \(requested)")
        }
        let chinese = try DefaultLocaleMatcher(supportedLocales: ["en", "zh", "zh-Hant"], fallbackLocale: "en",
                                               tiebreakerLocalesByLanguageCode: ["zh": ["zh-Hant", "zh"]])
        try expect(try chinese.matchFor("zh-TW").locale == "zh-Hant", "script-aware selection")
        try expect(try chinese.candidateChain(for: "zh-TW") == ["zh-TW", "zh-Hant", "en"], "resolution chain remains separate from negotiated selection")
        let fallbackElection = try DefaultLocaleMatcher(supportedLocales: ["en", "ro"], fallbackLocale: "mo")
        try expect(fallbackElection.fallbackLocale == "ro", "canonical unique fallback election")
        let canonicalChoice = try DefaultLocaleMatcher(supportedLocales: ["en", "mo", "ro"], fallbackLocale: "ron",
                                                       tiebreakerLocalesByLanguageCode: ["ro": ["mo", "ro"]])
        try expect(canonicalChoice.fallbackLocale == "mo", "ambiguous canonical fallback honors tiebreaker order")

        let exclusions = try DefaultLocaleMatcher(supportedLocales: ["en-US", "en-GB", "fr"], fallbackLocale: "en-US",
                                                 tiebreakerLocalesByLanguageCode: ["en": ["en-US", "en-GB"]])
        let excluded = try exclusions.matchFor([LanguageRange("en"), LanguageRange("en-us", weight: 0), LanguageRange("fr", weight: 0.5)])
        try expect(excluded.locale == "en-GB" && excluded.effectiveWeight == 1, "specific zero-quality excludes without excluding siblings")
        try expect(try exclusions.matchFor([LanguageRange("*"), LanguageRange("en-us", weight: 0)]).locale == "en-GB", "wildcard uses fallback language's tiebreaker when fallback excluded")
        let privateLocales = try DefaultLocaleMatcher(supportedLocales: ["en", "und", "und-Latn", "x-a", "x-b"], fallbackLocale: "en")
        try expect(try privateLocales.matchFor("und").matchType == .noMatch, "undetermined language has no exact preference semantics")
        try expect(try privateLocales.matchFor("x-a").matchType == .exact, "private-use can select an exact catalog")
        try expect(try privateLocales.matchFor([LanguageRange("x-*")]).matchType == .extendedRange, "private-use wildcard remains structural")

        let ranges33 = try (0..<33).map { index in
            try LanguageRange("q" + String(Unicode.Scalar(97 + index / 26)!) + String(Unicode.Scalar(97 + index % 26)!))
        }
        try expect(try simple.matchFor(Array(ranges33.prefix(32))).requestedLanguageRanges.count == 32, "32 ranges are accepted whole")
        try refusal("At most 32 language ranges are supported, but received 33") { _ = try simple.matchFor(ranges33) }
        let oversizedHeader = ranges33.map(\.range).joined(separator: ",")
        try expect(try simple.parseLanguageRanges(oversizedHeader).count == 33, "strict parsing has no matching-count cap")
        try expect(try simple.bestMatchForAcceptLanguage(oversizedHeader + ",fr;q=.5") == "en", "fail-soft expanded-count refusal uses fallback without truncation")
        try expect(try simple.bestMatchForAcceptLanguage(" ,\tfr\t;\tq=0.7, , ") == "fr", "HTTP OWS and empty members normalize before strict parser")
        try expect(try simple.bestMatchForAcceptLanguage(String(repeating: " ", count: 4_094) + "fr") == "fr", "4096-character header remains accepted")
        try expect(try simple.bestMatchForAcceptLanguage(String(repeating: " ", count: 4_095) + "fr") == "en", "4097-character header fails soft")
        try expect(try simple.bestMatchForAcceptLanguage("fr;q=bad") == "en", "grammar failure fails soft")
        try expect(try simple.bestMatchForAcceptLanguage(nil) == "en", "missing header fails soft")

        let rawNaN = try LanguageRange("fr", weight: .nan)
        try refusal("A matched locale result requires a finite effective weight greater than 0 and at most 1") {
            _ = try simple.matchFor([rawNaN, LanguageRange("en")])
        }
        try expect(try simple.matchFor([LanguageRange("zz", weight: .nan)]).matchType == .noMatch, "unrelated NaN preference can remain unmatched")
        try expect(try simple.matchFor([LanguageRange("fr", weight: -0.0), LanguageRange("fr", weight: 0.0)]).matchType == .noMatch, "signed-zero direct ranges remain exclusions")

        let retained = try LocaleMatchResult(requestedLanguageRanges: [LanguageRange("fr", weight: 0.7)], locale: "FR",
                                            languageRange: LanguageRange("fr", weight: 0.7), effectiveWeight: 0.7, matchType: .exact,
                                            fallbackLocale: "EN", consideredLocales: ["fr", "en"])
        try expect(try simple.validateSuppliedMatch(retained) === retained && retained.consideredLocales == ["fr", "en"], "validated supplied result preserves identity and caller considered order")
        try refusal("The matched language range must be present in requested language ranges") {
            _ = try LocaleMatchResult(requestedLanguageRanges: [LanguageRange("fr", weight: 0.7)], locale: "fr",
                                      languageRange: LanguageRange("fr"), effectiveWeight: .nan, matchType: .exact,
                                      fallbackLocale: "en", consideredLocales: ["en", "fr"])
        }
        try refusal("Considered locales must not contain duplicate language tag 'en'") {
            _ = try LocaleMatchResult(requestedLanguageRanges: [], locale: nil, languageRange: nil, effectiveWeight: nil,
                                      matchType: .noMatch, fallbackLocale: "fr", consideredLocales: ["en", "EN"])
        }
        try refusal("A matched locale result requires a range, weight, and non-NONE match type") {
            _ = try LocaleMatchResult(requestedLanguageRanges: [], locale: "en", languageRange: nil, effectiveWeight: nil,
                                      matchType: .noMatch, fallbackLocale: "en", consideredLocales: ["en"])
        }
        let foreign = try LocaleMatchResult(requestedLanguageRanges: [], locale: nil, languageRange: nil, effectiveWeight: nil,
                                           matchType: .noMatch, fallbackLocale: "de", consideredLocales: ["de"])
        try refusal("localeMatchSupplier returned a result for a different fallback locale") { _ = try simple.validateSuppliedMatch(foreign) }
        let aliases = try LocaleMatchResult(requestedLanguageRanges: [], locale: nil, languageRange: nil, effectiveWeight: nil,
                                           matchType: .noMatch, fallbackLocale: "en", consideredLocales: ["en", "mo"])
        let romanianContext = try DefaultLocaleMatcher(supportedLocales: ["en", "ro"], fallbackLocale: "en")
        try refusal("localeMatchSupplier returned a result for different supported locales") { _ = try romanianContext.validateSuppliedMatch(aliases) }

        try refusal("Tiebreaker language code 'en-US' must be a well-formed primary language subtag") {
            _ = try DefaultLocaleMatcher(supportedLocales: ["en"], fallbackLocale: "en", tiebreakerLocalesByLanguageCode: ["en-US": ["en"]])
        }
        try refusal("Tiebreaker language code 'und' must identify a primary language") {
            _ = try DefaultLocaleMatcher(supportedLocales: ["en"], fallbackLocale: "en", tiebreakerLocalesByLanguageCode: ["und": ["en"]])
        }
        try refusal("Tiebreaker language codes 'he' and 'iw' both normalize to 'he'") {
            _ = try DefaultLocaleMatcher(supportedLocales: ["he"], fallbackLocale: "he", tiebreakerLocalesByLanguageCode: ["he": ["he"], "iw": ["iw"]])
        }
        try refusal("Tiebreaker locales for language code 'en' must be an exact permutation of loaded locales [en-GB, en-US]; missing: [en-GB]; unrelated: []") {
            _ = try DefaultLocaleMatcher(supportedLocales: ["en-US", "en-GB"], fallbackLocale: "en-US", tiebreakerLocalesByLanguageCode: ["en": ["en-US"]])
        }
        try refusal("Specified fallback locale is 'de' but no matching localized strings locale was found. Known locales: [en]") {
            _ = try DefaultLocaleMatcher(supportedLocales: ["en"], fallbackLocale: "de", tiebreakerLocalesByLanguageCode: ["en-US": []])
        }

        let rootLocale = LocaleTag.forLanguageTag("und"), explicitUnd = LocaleTag.forLanguageTag("UND")
        try expect(rootLocale.tag == explicitUnd.tag && rootLocale != explicitUnd, "rendered tag collisions remain distinct native locale values")
        let typed = try DefaultLocaleMatcher(supportedLocales: [explicitUnd], fallbackLocale: explicitUnd)
        try expect(typed.supportedLocaleTags == [explicitUnd] && typed.fallbackLocaleTag == explicitUnd, "typed matcher retains configured locale fields")
        let typedUnmatched = try typed.matchFor([])
        try expect(typedUnmatched.fallbackLocaleTag == explicitUnd && typedUnmatched.consideredLocaleTags == [explicitUnd], "unmatched diagnostics retain locale fields")
        try expect(try typed.validateSuppliedMatch(typedUnmatched) === typedUnmatched, "typed contextual validation retains diagnostic identity")
        try expect(try typed.matchFor([LanguageRange("*")]).localeTag == explicitUnd, "election returns the supported locale carrier")
        let rootProjection = try LocaleMatchResult(requestedLanguageRanges: [], locale: nil, languageRange: nil, effectiveWeight: nil,
                                                   matchType: .noMatch, fallbackLocale: "und", consideredLocales: ["und"])
        try refusal("localeMatchSupplier returned a result for a different fallback locale") { _ = try typed.validateSuppliedMatch(rootProjection) }
        try refusal("The fallback locale must be present in considered locales") {
            _ = try LocaleMatchResult(requestedLanguageRanges: [], locale: nil, languageRange: nil, effectiveWeight: nil,
                                      matchType: .noMatch, fallbackLocale: rootLocale, consideredLocales: [explicitUnd])
        }
        let legacyNorwegian = LocaleTag.forLanguageTag("no-NO-x-lvariant-NY"), modernNorwegian = try LocaleTag("nn-NO")
        let typedNorwegian = try DefaultLocaleMatcher(supportedLocales: [legacyNorwegian], fallbackLocale: legacyNorwegian)
        let typedNorwegianMatch = try typedNorwegian.matchFor(legacyNorwegian)
        try expect(typedNorwegianMatch.localeTag == legacyNorwegian && typedNorwegianMatch.languageRange?.range == "nn-no", "locale request projects range spelling while selected carrier remains intact")
        try refusal("Tiebreaker locales for language code 'nn' must be an exact permutation of loaded locales [nn-NO]; missing: [nn-NO]; unrelated: [nn-NO]") {
            _ = try DefaultLocaleMatcher(supportedLocales: [legacyNorwegian], fallbackLocale: legacyNorwegian,
                                         tiebreakerLocalesByLanguageCode: ["nn": [modernNorwegian]])
        }

        try probeFailure(.parser) { _ = try MatcherProtocolProbe(parserMode: .customFailure).bestMatchForAcceptLanguage("fr") }
        try probeFailure(.negotiation) { _ = try MatcherProtocolProbe(throwsNegotiation: true).bestMatchForAcceptLanguage("fr") }
        try probeFailure(.emptyNegotiation) { _ = try MatcherProtocolProbe(throwsEmpty: true).bestMatchForAcceptLanguage(nil) }
        try expect(try MatcherProtocolProbe(parserMode: .grammarFailure).bestMatchForAcceptLanguage("fr") == "en", "custom grammar error alone fails soft")
        try expect(try MatcherProtocolProbe(parserMode: .alwaysFrench).bestMatchForAcceptLanguage(String(repeating: "😀", count: 2_048) + "f") == "en", "HTTP length budget counts UTF16 before invoking custom parser")
        return checks
    }
}

private enum MatcherProbeError: Error, Equatable { case parser, negotiation, emptyNegotiation }
private struct MatcherProtocolProbe: LocaleMatcher {
    enum ParserMode: Sendable { case ordinary, customFailure, grammarFailure, alwaysFrench }
    let fallbackLocale = "en"
    var parserMode: ParserMode = .ordinary
    var throwsNegotiation = false
    var throwsEmpty = false
    func parseLanguageRanges(_ ranges: String) throws -> [LanguageRange] {
        switch parserMode {
        case .customFailure: throw MatcherProbeError.parser
        case .grammarFailure: throw LanguageRangeError("range=")
        case .alwaysFrench: return [try LanguageRange("fr")]
        case .ordinary: return try LanguageRangeParser.parse(ranges)
        }
    }
    func matchFor(_ languageRanges: [LanguageRange]) throws -> LocaleMatchResult {
        if languageRanges.isEmpty && throwsEmpty { throw MatcherProbeError.emptyNegotiation }
        if !languageRanges.isEmpty && throwsNegotiation { throw MatcherProbeError.negotiation }
        return try LocaleMatchResult(requestedLanguageRanges: languageRanges, locale: languageRanges.isEmpty ? nil : "fr",
                                     languageRange: languageRanges.first, effectiveWeight: languageRanges.first?.weight,
                                     matchType: languageRanges.isEmpty ? .noMatch : .exact, fallbackLocale: "en", consideredLocales: ["en", "fr"])
    }
}
