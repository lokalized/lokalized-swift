import XCTest
@testable import Lokalized

final class RuntimeConstructionTests: XCTestCase {
    private func configuration(_ catalogs: [LocaleTag: LocalizedCatalog], fallback: LocaleTag,
                               limits: TranslationRuntimeLimits? = nil,
                               ties: [String: [LocaleTag]]? = nil) -> StringsConfiguration {
        StringsConfiguration(localizedStringSupplier: { catalogs }, localeSupplier: { _ in fallback },
            fallbackLocale: fallback, tiebreakerLocalesByLanguageCode: ties, runtimeLimits: limits)
    }

    func testSupplierRequirementsPrecedeSupplierInvocation() throws {
        let error = ConstructionTestError()
        let en = try LocaleTag("en")
        XCTAssertThrowsError(try DefaultStrings(configuration: StringsConfiguration(
            localizedStringSupplier: { throw error }, fallbackLocale: en))) {
            XCTAssertEqual(($0 as? ConfigurationError)?.message,
                "You must specify exactly one of 'localeSupplier' or 'localeMatchSupplier' when creating a DefaultStrings instance")
        }
        XCTAssertThrowsError(try DefaultStrings(configuration: StringsConfiguration(
            localizedStringSupplier: { throw error }, localeSupplier: { _ in en }, fallbackLocale: en))) {
            XCTAssertTrue(($0 as? ConstructionTestError) === error)
        }
    }

    func testSemanticValidationPrecedesFallbackAndAmbiguityChecks() throws {
        let invalid = try LocalizedString(key: "bad", translation: "{{CARDINALITY_ONE}}")
        let enUS = try LocaleTag("en-US"), enGB = try LocaleTag("en-GB")
        let input: [LocaleTag: LocalizedCatalog] = [enUS: .init(strings: [invalid]), enGB: .init(strings: [])]
        XCTAssertThrowsError(try DefaultStrings(configuration: configuration(input, fallback: LocaleTag("fr")))) {
            XCTAssertTrue(($0 as? ConfigurationError)?.message.hasPrefix("Invalid localized string 'bad'") == true)
        }
        XCTAssertThrowsError(try DefaultStrings(configuration: configuration(input, fallback: enUS))) {
            XCTAssertTrue(($0 as? ConfigurationError)?.message.hasPrefix("Invalid localized string 'bad'") == true)
        }
    }

    func testDuplicateKeysAreRetainedUntilConstruction() throws {
        let en = try LocaleTag("en")
        let first = try LocalizedString(key: "key", translation: "first")
        let second = try LocalizedString(key: "key", translation: "second")
        let catalog: LocalizedCatalog = ["key": first, "key": second]
        XCTAssertEqual(catalog.count, 2)
        XCTAssertThrowsError(try DefaultStrings(configuration: configuration([en: catalog], fallback: en))) {
            XCTAssertEqual(($0 as? ConfigurationError)?.message,
                "Duplicate localized string key 'key' encountered for locale 'en'")
        }
    }

    func testEagerCompilationPrecedesLaterDuplicateRefusal() throws {
        let en = try LocaleTag("en")
        let alternative = try LocalizedString(key: "n == 1", translation: "yes")
        let first = try LocalizedString(key: "key", translation: "default", alternatives: [alternative])
        let second = try LocalizedString(key: "key", translation: "duplicate")
        let config = try configuration([en: .init(strings: [first, second])], fallback: en,
            limits: TranslationRuntimeLimits(maximumExpressionTokens: 1))
        XCTAssertThrowsError(try DefaultStrings(configuration: config)) {
            let error = $0 as? TranslationEvaluationError
            XCTAssertEqual(error?.kind, .expression)
            XCTAssertTrue(error?.message.hasPrefix("Unable to compile whole-message alternative expression") == true)
            XCTAssertNotNil(error?.cause)
        }
    }

    func testCatalogEntryLabelMustMatchItsModelKey() throws {
        let en = try LocaleTag("en")
        let model = try LocalizedString(key: "actual", translation: "value")
        XCTAssertThrowsError(try DefaultStrings(configuration: configuration([en: ["different": model]], fallback: en))) {
            XCTAssertEqual(($0 as? ConfigurationError)?.message,
                "Catalog entry key 'different' does not match localized string key 'actual' for locale 'en'")
        }
    }

    func testInspectionRetainsExactKeysAndRequiresLoadedLocaleIdentity() throws {
        let en = try LocaleTag("en"), fr = try LocaleTag("fr")
        let composed = try LocalizedString(key: "é", translation: "a")
        let decomposed = try LocalizedString(key: "e\u{0301}", translation: "b")
        let strings = try DefaultStrings(configuration: configuration([
            en: .init(strings: [composed, decomposed]), fr: .init(strings: [composed])], fallback: en))
        XCTAssertEqual(try strings.getKeysForLocale(en), Set([composed.key, decomposed.key]))
        XCTAssertEqual(try strings.getMissingKeys(sourceLocale: en, targetLocale: fr), [decomposed.key])
        XCTAssertThrowsError(try strings.getKeysForLocale(LocaleTag("en-US"))) {
            XCTAssertEqual(($0 as? TranslationEvaluationError)?.message, "Locale 'en-US' is not supported")
        }
        XCTAssertThrowsError(try strings.getMissingKeys(sourceLocale: LocaleTag("de"), targetLocale: fr)) {
            XCTAssertEqual(($0 as? TranslationEvaluationError)?.message, "Source locale 'de' is not supported")
        }
        XCTAssertThrowsError(try strings.getMissingKeys(sourceLocale: en, targetLocale: LocaleTag("de"))) {
            XCTAssertEqual(($0 as? TranslationEvaluationError)?.message, "Target locale 'de' is not supported")
        }
    }

    func testInspectionUsesTypedLocaleIdentityDespiteEqualRenderedTags() throws {
        let root = LocaleTag.forLanguageTag("und"), named = LocaleTag.forLanguageTag("UND")
        XCTAssertEqual(root.tag, named.tag)
        XCTAssertNotEqual(root, named)
        let model = try LocalizedString(key: "key", translation: "value")
        let strings = try DefaultStrings(configuration: configuration([named: .init(strings: [model])], fallback: root))
        XCTAssertEqual(strings.fallbackLocaleTag, named)
        XCTAssertEqual(try strings.getKeysForLocale(named), [model.key])
        XCTAssertThrowsError(try strings.getKeysForLocale(root))
        XCTAssertEqual(try strings.get("key", options: .forLocale(root)), "value")
    }
}
private final class ConstructionTestError: Error, Sendable {}
