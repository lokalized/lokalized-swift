import Foundation
import XCTest
@testable import Lokalized
import LokalizedConformanceSupport

final class PluralRulesTests: XCTestCase {
    func testIntegerAndDecimalScaleRemainDistinct() throws {
        XCTAssertEqual(try Cardinality.forNumber(1, locale: "en"), .one)
        XCTAssertEqual(try Cardinality.forNumber(ExactDecimal("1.0"), locale: "en"), .other)
        XCTAssertEqual(try Cardinality.forNumber(1, visibleDecimalPlaces: 1, locale: "en"), .other)
        XCTAssertEqual(try Cardinality.forNumber(ExactDecimal("1.00"), locale: "af"), .one)
        XCTAssertEqual(try Cardinality.forNumber(ExactDecimal("0.5"), locale: "ak"), .other)
        XCTAssertEqual(try Cardinality.forNumber(ExactDecimal("1.50"), locale: "ru"), .other)
    }

    func testExactHugeModuloAndNegativeAbsoluteValue() throws {
        let huge = String(repeating: "9", count: 250) + "22"
        XCTAssertEqual(try Cardinality.forNumber(.bigInteger(huge), locale: "pl"), .few)
        XCTAssertEqual(try Cardinality.forNumber(.bigInteger("-" + huge), locale: "pl"), .few)
        XCTAssertEqual(try Ordinality.forNumber(.bigInteger(huge), locale: "en"), .two)
        XCTAssertEqual(try Ordinality.forNumber(112, locale: "en"), .other)
    }

    func testCompactOperandsShiftAndExponentRelations() throws {
        let million = try PluralOperands(.decimal(ExactDecimal("1")), compactExponent: 6)
        XCTAssertEqual(million.n.plainString, "1000000")
        XCTAssertEqual(try Cardinality.forOperands(million, locale: "fr"), .many)
        XCTAssertEqual(try Cardinality.forOperands(million, locale: "en"), .other)
        let compact = try PluralOperands(.decimal(ExactDecimal("1.2")), compactExponent: 3)
        XCTAssertEqual(try Cardinality.forOperands(compact, locale: "fr"), .other)
        let exponentOnly = try PluralOperands(.decimal(ExactDecimal("1.0000001")), compactExponent: 6)
        XCTAssertEqual(try Cardinality.forOperands(exponentOnly, locale: "fr"), .many)
    }

    func testCandidateLadderKeepsPortugueseRegionAndRootSupport() throws {
        XCTAssertEqual(try Cardinality.forNumber(0, locale: "pt"), .one)
        XCTAssertEqual(try Cardinality.forNumber(0, locale: "pt-PT"), .other)
        XCTAssertEqual(try Cardinality.forNumber(0, locale: "pT-lATN-pt"), .other)
        XCTAssertEqual(try Cardinality.forNumber(1, locale: "zh-Hant-MO"), .other)
        XCTAssertEqual(try Cardinality.forNumber(1, locale: "und"), .other)
        XCTAssertEqual(try Cardinality.forNumber(1, locale: "und-Latn"), .other)
        XCTAssertEqual(try Cardinality.forNumber(1, locale: "x-private"), .other)
        XCTAssertEqual(try Ordinality.forNumber(1, locale: "x-private"), .other)
        XCTAssertEqual(try Cardinality.supportedCardinalitiesForLocale("x-private"), [.other])
        XCTAssertEqual(try Ordinality.supportedOrdinalitiesForLocale("x-private"), [.other])
        XCTAssertEqual(try Cardinality.forNumber(1, locale: "iw"), .one)
    }

    func testOrdinalRootFallbackGatesOnCardinalSupport() throws {
        XCTAssertEqual(try Ordinality.forNumber(2, locale: "en"), .two)
        XCTAssertEqual(try Ordinality.forNumber(3, locale: "en"), .few)
        XCTAssertEqual(try Ordinality.supportedOrdinalitiesForLocale("asa"), [.other])
        XCTAssertEqual(try Ordinality.forNumber(1, locale: "asa"), .other)
        XCTAssertEqual(try Ordinality.supportedOrdinalitiesForLocale("zz"), [])
        XCTAssertEqual(try Cardinality.supportedCardinalitiesForLocale("zz"), [])
        for locale in ["zz", "zxx"] {
            XCTAssertThrowsError(try Ordinality.forNumber(1, locale: locale)) { error in
                XCTAssertEqual((error as? UnsupportedLocaleError)?.locale, locale)
                XCTAssertEqual((error as? UnsupportedLocaleError)?.message, "Unsupported locale '\(locale)' was provided")
            }
        }
    }

    func testCardinalRangesExplicitRowsAndEndFallback() throws {
        XCTAssertEqual(try Cardinality.forRange(.one, .one, locale: "en"), .one) // missing row
        XCTAssertEqual(try Cardinality.forRange(.other, .one, locale: "en"), .other) // explicit row
        XCTAssertEqual(try Cardinality.forRange(.zero, .two, locale: "ar"), .zero)
        XCTAssertEqual(try Cardinality.forRange(.few, .two, locale: "asa"), .two) // no range group
        XCTAssertEqual(try Cardinality.forRange(.few, .two, locale: "x-private"), .two)
        XCTAssertEqual(try Cardinality.forRange(.one, .one, locale: "pt-Latn-PT"), .one)
        XCTAssertThrowsError(try Cardinality.forRange(.one, .one, locale: "zxx")) { error in
            XCTAssertTrue(error is UnsupportedLocaleError)
        }
    }

    func testSupportInventoriesAreDeterministicAndEnumOrdered() throws {
        XCTAssertEqual(try Cardinality.supportedCardinalitiesForLocale("ar"), [.zero, .one, .two, .few, .many, .other])
        XCTAssertEqual(try Ordinality.supportedOrdinalitiesForLocale("en"), [.one, .two, .few, .other])
        let cardinal = Cardinality.getSupportedLocaleTags()
        let ordinal = Ordinality.getSupportedLocaleTags()
        XCTAssertEqual(cardinal.count, 224)
        XCTAssertEqual(cardinal, cardinal.sorted())
        XCTAssertEqual(ordinal, ordinal.sorted())
        XCTAssertTrue(ordinal.contains("asa"))
        XCTAssertTrue(cardinal.contains("und"))
        XCTAssertFalse(cardinal.contains("root"))
        XCTAssertTrue(cardinal.contains("pt-PT"))
    }

    func testJavaExampleContainersPreserveScaleAndInfiniteFlag() throws {
        let integer = try Cardinality.exampleIntegerValuesForLocale("af")
        XCTAssertEqual(integer[.one]?.values, [1])
        XCTAssertEqual(integer[.one]?.isInfinite, false)
        XCTAssertEqual(integer[.other]?.isInfinite, true)
        let decimal = try Cardinality.exampleDecimalValuesForLocale("af")
        XCTAssertEqual(decimal[.one]?.values.map(\.plainString), ["1.0", "1.00", "1.000", "1.0000"])
        XCTAssertEqual(decimal[.one]?.isInfinite, false)
        XCTAssertEqual(decimal[.other]?.isInfinite, true)
        XCTAssertTrue(try Cardinality.exampleIntegerValuesForLocale("zz").isEmpty)
        XCTAssertTrue(try Cardinality.exampleDecimalValuesForLocale("zz").isEmpty)
        XCTAssertTrue(try Ordinality.exampleIntegerValuesForLocale("asa")[.other]?.isInfinite == true)
        XCTAssertTrue(try Ordinality.exampleIntegerValuesForLocale("zz").isEmpty)
        let sample: Lokalized.Range<Int> = .ofInfiniteValues(1, 10, 100)
        XCTAssertEqual(Array(sample), [1, 10, 100])
        XCTAssertEqual(sample, .init(values: [1, 10, 100], isInfinite: true))
        XCTAssertNotEqual(Lokalized.Range<Int>.emptyFiniteRange(), .emptyInfiniteRange())
    }

    func testClassifierUsesCallerNumericLimitsBeforeLocaleLookup() throws {
        let limits = try TranslationRuntimeLimits(maximumNumberPrecision: 2)
        XCTAssertThrowsError(try Cardinality.forNumber(.bigInteger("123"), locale: "zz", runtimeLimits: limits)) { error in
            XCTAssertTrue(error is NumericError)
        }
        XCTAssertThrowsError(try Ordinality.forNumber(1, visibleDecimalPlaces: -1, locale: "en")) { error in
            XCTAssertTrue(error is NumericError)
        }
        XCTAssertThrowsError(try Cardinality.forNumber(ExactDecimal("1.1"), visibleDecimalPlaces: 0, locale: "en")) { error in
            XCTAssertTrue(error is NumericError)
        }
    }

    func testNativeMalformedLocaleError() throws {
        for locale in ["", "en_US", "en--US", "é", "x"] {
            XCTAssertThrowsError(try Cardinality.supportedCardinalitiesForLocale(locale)) { error in
                XCTAssertEqual((error as? PluralLocaleError)?.locale, locale)
            }
        }
    }

    func testCompletePinnedCLDRVectorsAndExamples() throws {
        let report = try ConformanceRunner.pluralDataAudit(referenceDirectory: referenceDirectory)
        XCTAssertEqual(report.status, "passed", report.failures.joined(separator: "\n"))
        XCTAssertEqual(report.failedChecks, 0)
        XCTAssertEqual(report.cardinalSamples, 12_396)
        XCTAssertEqual(report.ordinalSamples, 2_645)
        XCTAssertEqual(report.rangeCells, 8_064)
        XCTAssertEqual(report.supportInventories, 450)
        XCTAssertEqual(report.integerExampleRanges, 796)
        XCTAssertEqual(report.decimalExampleRanges, 440)
        XCTAssertEqual(report.checks, 24_227)
        XCTAssertEqual(report.compiledBytecodeWords, 1_661)
        XCTAssertEqual(report.compiledBytecodeBytes, 6_644)
        XCTAssertEqual(report.conditionPrograms, 96)
        XCTAssertEqual(report.vectorBytes, 48_325)
        XCTAssertEqual(report.pluralSourceBytes, 79_598)
    }

    func testPluralAuditRefusesMutatedReference() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for name in ["cldr-plural-data.json", "cldr-conformance-vectors.json"] {
            try FileManager.default.copyItem(at: referenceDirectory.appendingPathComponent(name), to: temporary.appendingPathComponent(name))
        }
        let vector = temporary.appendingPathComponent("cldr-conformance-vectors.json")
        var changed = try Data(contentsOf: vector)
        changed.append(0x20)
        try changed.write(to: vector)
        XCTAssertThrowsError(try ConformanceRunner.pluralDataAudit(referenceDirectory: temporary)) { error in
            XCTAssertTrue(String(describing: error).contains("digest mismatch"))
        }
    }

    private var referenceDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Reference")
    }
}
