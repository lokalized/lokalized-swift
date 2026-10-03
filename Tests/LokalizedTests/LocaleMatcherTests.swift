import XCTest
@testable import Lokalized
import LokalizedConformanceSupport

final class LocaleMatcherTests: XCTestCase {
    func testStandaloneNativeMatcherQualification() throws {
        XCTAssertGreaterThan(try ConformanceRunner.matcherSelfTest(), 50)
    }

    func testSpecificQualityOverridesBroadPreferenceAndKeepsCallerRanges() throws {
        let matcher = try DefaultLocaleMatcher(supportedLocales: ["fr", "en-US", "en-GB"], fallbackLocale: "en-US",
                                              tiebreakerLocalesByLanguageCode: ["en": ["en-US", "en-GB"]])
        let ranges = [try LanguageRange("en"), try LanguageRange("en-us", weight: 0.2), try LanguageRange("fr", weight: 0.5)]
        let result = try matcher.matchFor(ranges)
        XCTAssertEqual(result.locale, "en-GB")
        XCTAssertEqual(result.effectiveWeight, 1)
        XCTAssertEqual(result.requestedLanguageRanges, ranges)
        XCTAssertEqual(result.languageRange, ranges[0])
        XCTAssertEqual(result.consideredLocales, ["en-GB", "en-US", "fr"])
    }

    func testExtendedFilteringCannotCrossExtensionSingleton() throws {
        let matcher = try DefaultLocaleMatcher(supportedLocales: ["de-Latn-DE", "de-DE-u-co-phonebk", "fr"], fallbackLocale: "fr",
                                              tiebreakerLocalesByLanguageCode: ["de": ["de-Latn-DE", "de-DE-u-co-phonebk"]])
        XCTAssertEqual(try matcher.matchFor([LanguageRange("de-*-de")]).locale, "de-Latn-DE")
        XCTAssertEqual(try matcher.matchFor([LanguageRange("de-*-phonebk")]).matchType, .noMatch)
    }

    func testJDKAndIanaEquivalenceModesAreExplicitAndPinned() throws {
        let registry = try DefaultLocaleMatcher(supportedLocales: ["en", "mrd-MM"], fallbackLocale: "en", languageRangeEquivalents: .ianaRegistry)
        let jdk = try DefaultLocaleMatcher(supportedLocales: ["en", "mrd-MM"], fallbackLocale: "en", languageRangeEquivalents: .jdk)
        XCTAssertEqual(registry.languageRangeEquivalents, .ianaRegistry)
        XCTAssertEqual(jdk.languageRangeEquivalents, .jdk)
        XCTAssertEqual(try registry.parseLanguageRanges("mgp-BU"), try LanguageRangeParser.parse("mgp-BU", equivalents: .ianaRegistry))
        XCTAssertEqual(try jdk.parseLanguageRanges("mgp-BU"), try LanguageRangeParser.parse("mgp-BU", equivalents: .jdk))
        XCTAssertEqual(try registry.matchFor("mgp-BU").locale, "mrd-MM")
    }

    func testStrictStringAndTypedLocaleRebuildabilityDiagnostics() throws {
        let matcher = try DefaultLocaleMatcher(supportedLocales: ["en"], fallbackLocale: "en")
        let malformed = LocaleTag.forLanguageTag("en-x-lvariant-NY")
        XCTAssertThrowsError(try matcher.matchFor(malformed)) { error in
            XCTAssertEqual((error as? LocaleTagError)?.message, "Requested locale 'en__NY' is not a well-formed IETF BCP 47 locale")
        }
        XCTAssertThrowsError(try matcher.matchFor("en-x-lvariant-NY")) { error in
            XCTAssertEqual((error as? LocaleTagError)?.message, "Requested locale 'en__NY' is not a well-formed IETF BCP 47 locale")
        }
        XCTAssertThrowsError(try matcher.matchFor("en_US")) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "Requested locale 'en_US' is not a well-formed IETF BCP 47 locale")
        }
    }

    func testResultValidationPhaseOrder() throws {
        let tooMany = try Array(repeating: LanguageRange("en"), count: 33)
        XCTAssertThrowsError(try LocaleMatchResult(requestedLanguageRanges: tooMany, locale: "en-x-lvariant-NY", languageRange: nil,
                                                  effectiveWeight: nil, matchType: .noMatch, fallbackLocale: "en", consideredLocales: [])) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "At most 32 language ranges are supported, but received 33")
        }
        XCTAssertThrowsError(try LocaleMatchResult(requestedLanguageRanges: [], locale: "en-x-lvariant-NY", languageRange: nil,
                                                  effectiveWeight: nil, matchType: .noMatch, fallbackLocale: "en", consideredLocales: [])) { error in
            XCTAssertEqual((error as? LocaleTagError)?.message, "Selected locale 'en__NY' is not a well-formed IETF BCP 47 locale")
        }
        XCTAssertThrowsError(try LocaleMatchResult(requestedLanguageRanges: [], locale: nil, languageRange: nil,
                                                  effectiveWeight: nil, matchType: .exact, fallbackLocale: "en-x-lvariant-NY", consideredLocales: [])) { error in
            XCTAssertEqual((error as? LocaleTagError)?.message, "Fallback locale 'en__NY' is not a well-formed IETF BCP 47 locale")
        }
        XCTAssertThrowsError(try LocaleMatchResult(requestedLanguageRanges: [], locale: nil, languageRange: nil,
                                                  effectiveWeight: nil, matchType: .noMatch, fallbackLocale: "en", consideredLocales: ["en-x-lvariant-NY", "en"])) { error in
            XCTAssertEqual((error as? LocaleTagError)?.message, "Considered locale 'en__NY' is not a well-formed IETF BCP 47 locale")
        }
    }

    func testResultFiniteWeightAndContainmentInvariants() throws {
        let requested = [try LanguageRange("fr")]
        for weight in [Double.nan, .infinity, 0, -0.0, -1, 1.1] {
            XCTAssertThrowsError(try LocaleMatchResult(requestedLanguageRanges: requested, locale: "fr", languageRange: requested[0],
                                                      effectiveWeight: weight, matchType: .exact, fallbackLocale: "en", consideredLocales: ["en", "fr"])) { error in
                XCTAssertEqual((error as? LocaleMatcherError)?.message, "A matched locale result requires a finite effective weight greater than 0 and at most 1")
            }
        }
        XCTAssertThrowsError(try LocaleMatchResult(requestedLanguageRanges: [], locale: nil, languageRange: nil, effectiveWeight: nil,
                                                  matchType: .noMatch, fallbackLocale: "en", consideredLocales: [])) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "The fallback locale must be present in considered locales")
        }
        XCTAssertThrowsError(try LocaleMatchResult(requestedLanguageRanges: requested, locale: "fr", languageRange: requested[0], effectiveWeight: 1,
                                                  matchType: .exact, fallbackLocale: "en", consideredLocales: ["en"])) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "The selected locale must be present in considered locales")
        }
    }

    func testImmutableResultEqualityAndRetainedIdentity() throws {
        let matcher = try DefaultLocaleMatcher(supportedLocales: ["en", "fr"], fallbackLocale: "en")
        let result = try matcher.matchFor("fr")
        let equivalent = try matcher.matchFor("fr")
        XCTAssertEqual(result, equivalent)
        XCTAssertEqual(Set([result, equivalent]).count, 1)
        XCTAssertFalse(result === equivalent)
        XCTAssertTrue(try matcher.validateSuppliedMatch(result) === result)
        let reordered = try LocaleMatchResult(requestedLanguageRanges: result.requestedLanguageRanges, locale: result.locale,
                                              languageRange: result.languageRange, effectiveWeight: result.effectiveWeight, matchType: result.matchType,
                                              fallbackLocale: result.fallbackLocale, consideredLocales: ["fr", "en"])
        XCTAssertNotEqual(result, reordered)
        XCTAssertTrue(try matcher.validateSuppliedMatch(reordered) === reordered)
    }

    func testSingleExactPreferencePreservesQualityAndConfiguredTagIdentity() throws {
        let tags = [try LocaleTag("en-US"), try LocaleTag("mo"), try LocaleTag("qaa"),
                    try LocaleTag("x-a"), try LocaleTag("en-US-u-nu-latn"),
                    LocaleTag.forLanguageTag("no-NO-x-lvariant-NY")]
        for mode in [LanguageRangeEquivalents.ianaRegistry, .jdk] {
            for tag in tags {
                let matcher = try DefaultLocaleMatcher(supportedLocales: [tag], fallbackLocale: tag,
                                                      languageRangeEquivalents: mode)
                for weight in [1.0, 0.2, Double.leastNonzeroMagnitude] {
                    let preference = try LanguageRange(tag.tag.uppercased(), weight: weight)
                    let result = try matcher.matchFor([preference])
                    XCTAssertEqual(result.localeTag, tag)
                    XCTAssertEqual(result.matchType, .exact)
                    XCTAssertEqual(result.languageRange, preference)
                    XCTAssertEqual(result.requestedLanguageRanges, [preference])
                    XCTAssertEqual(result.effectiveWeight?.bitPattern, weight.bitPattern)
                    XCTAssertEqual(result.fallbackLocaleTag, tag)
                    XCTAssertEqual(result.consideredLocaleTags, [tag])
                    let repeated = try matcher.matchFor([preference])
                    XCTAssertEqual(repeated, result)
                    XCTAssertFalse(repeated === result)
                }
            }
        }
    }

    func testSingleLoadedPreferenceKeepsExclusionsAndUndeterminedSemantics() throws {
        let matcher = try DefaultLocaleMatcher(supportedLocales: ["en"], fallbackLocale: "en")
        for weight in [0.0, -0.0] {
            let preference = try LanguageRange("en", weight: weight)
            let result = try matcher.matchFor([preference])
            XCTAssertEqual(result.matchType, .noMatch)
            XCTAssertNil(result.locale)
            XCTAssertEqual(result.requestedLanguageRanges[0].weight.bitPattern, weight.bitPattern)
        }
        XCTAssertThrowsError(try matcher.matchFor([LanguageRange("en", weight: .nan)])) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message,
                           "A matched locale result requires a finite effective weight greater than 0 and at most 1")
        }
        for (tag, selected) in [("und", "und"), ("und-Latn", "und-Latn"), ("und-x-foo", "x-foo")] {
            let undetermined = try DefaultLocaleMatcher(supportedLocales: [tag], fallbackLocale: tag)
            XCTAssertEqual(try undetermined.matchFor([LanguageRange(tag)]).matchType, .noMatch)
            XCTAssertEqual(try undetermined.matchFor([LanguageRange("*")]).locale, selected)
        }
    }

    func testExactPreferenceCompetesWithOtherLoadedLocalesAndCallerRanges() throws {
        let matcher = try DefaultLocaleMatcher(supportedLocales: ["fr", "en-US", "en-GB"], fallbackLocale: "fr",
                                              tiebreakerLocalesByLanguageCode: ["en": ["en-GB", "en-US"]])
        let exact = try LanguageRange("EN-us", weight: 0.2)
        let single = try matcher.matchFor([exact])
        XCTAssertEqual(single.locale, "en-US")
        XCTAssertEqual(single.matchType, .exact)
        XCTAssertEqual(single.consideredLocales, ["en-GB", "en-US", "fr"])
        XCTAssertEqual(single.fallbackLocale, "fr")
        let competing = [exact, try LanguageRange("fr", weight: 0.5)]
        XCTAssertEqual(try matcher.matchFor(competing).locale, "fr")
        let excluded = [exact, try LanguageRange("en-us", weight: 0)]
        XCTAssertEqual(try matcher.matchFor(excluded).locale, "en-US")
        let narrower = [try LanguageRange("en"), try LanguageRange("en-us", weight: 0)]
        XCTAssertEqual(try matcher.matchFor(narrower).locale, "en-GB")
    }

    func testTiebreakerConfigurationRejectsDuplicatesAndMissingAmbiguity() throws {
        XCTAssertThrowsError(try DefaultLocaleMatcher(supportedLocales: ["en-US", "en-GB"], fallbackLocale: "en-US")) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "You must specify tiebreaker locales via 'tiebreakerLocalesByLanguageCode' to resolve ambiguity for language code 'en' because localized strings exist for the following locale[s]: [en-GB, en-US]")
        }
        XCTAssertThrowsError(try DefaultLocaleMatcher(supportedLocales: ["en"], fallbackLocale: "en", tiebreakerLocalesByLanguageCode: ["en": ["en", "EN"]])) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "Duplicate tiebreaker locale 'en' encountered for language code 'en'")
        }
        XCTAssertThrowsError(try DefaultLocaleMatcher(supportedLocales: ["iw", "he"], fallbackLocale: "he")) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "Localized strings locales 'he' and 'he' both use IETF BCP 47 language tag 'he'")
        }
        XCTAssertThrowsError(try DefaultLocaleMatcher(supportedLocales: ["en"], fallbackLocale: "en", tiebreakerLocalesByLanguageCode: ["de": ["de"]])) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "Tiebreaker language code 'de' has no localized strings locales")
        }
    }

    func testLocaleTagConfigurationConvenienceAndSynthesizedIdentityTiebreakers() throws {
        let matcher = try DefaultLocaleMatcher(supportedLocales: [LocaleTag("en"), LocaleTag("fr")], fallbackLocale: LocaleTag("en"))
        XCTAssertEqual(matcher.supportedLocales, ["en", "fr"])
        XCTAssertEqual(matcher.tiebreakerLocalesByLanguageCode, ["en": ["en"], "fr": ["fr"]])
        XCTAssertEqual(try matcher.bestMatchFor(LocaleTag("fr-CA")), "fr")
    }

    func testTypedLocaleIdentitySurvivesConfigurationElectionAndResults() throws {
        let root = LocaleTag.forLanguageTag("und"), explicitUnd = LocaleTag.forLanguageTag("UND")
        XCTAssertEqual(root.tag, explicitUnd.tag)
        XCTAssertNotEqual(root, explicitUnd)
        let matcher = try DefaultLocaleMatcher(supportedLocales: [explicitUnd], fallbackLocale: explicitUnd)
        XCTAssertEqual(matcher.supportedLocaleTags, [explicitUnd])
        XCTAssertEqual(matcher.fallbackLocaleTag, explicitUnd)
        let unmatched = try matcher.matchFor([])
        XCTAssertEqual(unmatched.fallbackLocaleTag, explicitUnd)
        XCTAssertEqual(unmatched.consideredLocaleTags, [explicitUnd])
        XCTAssertTrue(try matcher.validateSuppliedMatch(unmatched) === unmatched)
        let wildcard = try matcher.matchFor([LanguageRange("*")])
        XCTAssertEqual(wildcard.localeTag, explicitUnd)
        XCTAssertEqual(wildcard.locale, "und")
        let projected = try LocaleMatchResult(requestedLanguageRanges: [], locale: nil, languageRange: nil, effectiveWeight: nil,
                                             matchType: .noMatch, fallbackLocale: "und", consideredLocales: ["und"])
        XCTAssertThrowsError(try matcher.validateSuppliedMatch(projected)) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "localeMatchSupplier returned a result for a different fallback locale")
        }
        XCTAssertThrowsError(try LocaleMatchResult(requestedLanguageRanges: [], locale: nil, languageRange: nil, effectiveWeight: nil,
                                                  matchType: .noMatch, fallbackLocale: root, consideredLocales: [explicitUnd])) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "The fallback locale must be present in considered locales")
        }
        XCTAssertThrowsError(try DefaultLocaleMatcher(supportedLocales: [root, explicitUnd], fallbackLocale: root)) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "Localized strings locales '' and 'und' both use IETF BCP 47 language tag 'und'")
        }
        let legacy = LocaleTag.forLanguageTag("no-NO-x-lvariant-NY"), modern = try LocaleTag("nn-NO")
        XCTAssertEqual(legacy.tag, modern.tag)
        XCTAssertNotEqual(legacy, modern)
        let norwegian = try DefaultLocaleMatcher(supportedLocales: [legacy], fallbackLocale: legacy)
        let result = try norwegian.matchFor(legacy)
        XCTAssertEqual(result.languageRange?.range, "nn-no")
        XCTAssertEqual(result.matchType, .exact)
        XCTAssertEqual(result.localeTag, legacy)
        XCTAssertEqual(norwegian.tiebreakerLocaleTagsByLanguageCode, ["nn": [legacy]])
        XCTAssertThrowsError(try DefaultLocaleMatcher(supportedLocales: [legacy], fallbackLocale: legacy,
                                                      tiebreakerLocalesByLanguageCode: ["nn": [modern]])) { error in
            XCTAssertEqual((error as? LocaleMatcherError)?.message, "Tiebreaker locales for language code 'nn' must be an exact permutation of loaded locales [nn-NO]; missing: [nn-NO]; unrelated: [nn-NO]")
        }
    }

    func testConcurrentImmutableMatcherUse() async throws {
        let matcher = try DefaultLocaleMatcher(supportedLocales: ["en", "de", "fr"], fallbackLocale: "en")
        try await withThrowingTaskGroup(of: (String, LocaleMatchResult).self) { group in
            for index in 0..<60 {
                let request = ["en", "de", "fr"][index % 3]
                group.addTask { (request, try matcher.matchFor(request)) }
            }
            for try await (request, result) in group { XCTAssertEqual(result.locale, request) }
        }
    }
}
