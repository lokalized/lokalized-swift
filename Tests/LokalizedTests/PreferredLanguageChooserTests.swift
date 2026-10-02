import Foundation
import XCTest
@testable import Lokalized
@testable import LokalizedConformanceSupport

final class PreferredLanguageChooserTests: XCTestCase {
    func testStandaloneOrderedPreferenceQualification() throws {
        XCTAssertGreaterThan(try ConformanceRunner.preferredLanguageSelfTest(), 40)
    }

    func testTraditionalChinesePreferencePrecedesEnglishAndRetainsDirectDiagnostics() throws {
        let matcher = try DefaultLocaleMatcher(supportedLocales: ["en", "zh-Hant"], fallbackLocale: "en")
        let match = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["zh-TW", "en"], using: matcher)
        XCTAssertEqual(match.locale, "zh-Hant")
        XCTAssertEqual(match.requestedLanguageRanges.map(\.range), ["zh-tw"])
        XCTAssertNotNil(match.effectiveWeight)
        let reversed = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["en", "zh-TW"], using: matcher)
        XCTAssertEqual(reversed.locale, "en")
    }

    func testMalformedPreferencesConsumeRawSlotsWithoutReachingMatcher() throws {
        let matcher = try DefaultLocaleMatcher(supportedLocales: ["en", "fr"], fallbackLocale: "en")
        let atBoundary = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(Array(repeating: "!!", count: 31) + ["fr"], using: matcher)
        let beyondBoundary = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(Array(repeating: "!!", count: 32) + ["fr"], using: matcher)
        XCTAssertEqual(atBoundary.locale, "fr")
        XCTAssertFalse(beyondBoundary.isMatch)
        XCTAssertEqual(beyondBoundary.matchType, .noMatch)
        XCTAssertEqual(beyondBoundary.fallbackLocale, "en")
        XCTAssertTrue(beyondBoundary.requestedLanguageRanges.isEmpty)
        let nativeMalformed = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["en-x-lvariant-NY", "fr"], using: matcher)
        XCTAssertEqual(nativeMalformed.locale, "fr")
    }

    func testCustomMatcherFailuresPropagateAndAppleConvenienceDoesNotSwallowThem() throws {
        let marker = PreferredTestError()
        let matcher = PreferredThrowingMatcher(marker: marker)
        XCTAssertThrowsError(try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["fr", "en"], using: matcher)) { error in
            XCTAssertTrue((error as? PreferredTestError) === marker)
        }
        XCTAssertThrowsError(try PreferredLanguageChooser.chooseLocaleForPreferredLanguages([], using: matcher)) { error in
            XCTAssertTrue((error as? PreferredTestError) === marker)
        }
        XCTAssertThrowsError(try PreferredLanguageChooser.chooseAppleLocale(using: matcher)) { error in
            XCTAssertTrue((error as? PreferredTestError) === marker)
        }
    }

    func testApplePreferencesAreOnlyInputToConfiguredPinnedMatcher() throws {
        let matcher = try DefaultLocaleMatcher(supportedLocales: ["en", "fr", "zh-Hant"], fallbackLocale: "en")
        let result = try PreferredLanguageChooser.chooseAppleLocale(using: matcher)
        XCTAssertEqual(result.fallbackLocaleTag, matcher.fallbackLocaleTag)
        XCTAssertEqual(result.consideredLocaleTags, matcher.supportedLocaleTags)
        if let selected = result.localeTag { XCTAssertTrue(matcher.supportedLocaleTags.contains(selected)) }
    }

    func testExplicitPreferencesProduceIndependentRuntimeContexts() throws {
        let en = try LocaleTag("en")
        let fr = try LocaleTag("fr")
        let catalogs: [LocaleTag: LocalizedCatalog] = [
            en: .init(strings: [try LocalizedString(key: "k", translation: "English")]),
            fr: .init(strings: [try LocalizedString(key: "k", translation: "Français")])
        ]
        let strings = try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { catalogs },
            localeSupplier: { _ in en }, fallbackLocale: en))
        let first = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["fr"], using: strings)
        let second = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["en"], using: strings)
        let french = try strings.getResult("k", options: .forLocaleMatch(first))
        let english = try strings.getResult("k", options: .forLocaleMatch(second))
        XCTAssertEqual(french.translation, "Français")
        XCTAssertEqual(english.translation, "English")
        XCTAssertTrue(french.localeMatchResult === first)
        XCTAssertTrue(english.localeMatchResult === second)
        XCTAssertEqual(try strings.get("k"), "English")
    }
}

private final class PreferredTestError: Error, Sendable {}
private struct PreferredThrowingMatcher: LocaleMatcher {
    let marker: PreferredTestError
    var fallbackLocale: String { "en" }
    func matchFor(_ locale: String) throws -> LocaleMatchResult { throw marker }
    func matchFor(_ languageRanges: [LanguageRange]) throws -> LocaleMatchResult { throw marker }
}
