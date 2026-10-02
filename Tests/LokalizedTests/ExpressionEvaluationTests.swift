import XCTest
import Foundation
import Lokalized

final class ExpressionEvaluationTests: XCTestCase {
    private let english = try! LocaleTag("en")

    private func evaluate(_ source: String, _ context: [ExactString: PlaceholderValue] = [:], locale: LocaleTag? = nil,
                          limits: TranslationRuntimeLimits = .defaults, resolver: PhoneticResolver? = nil) throws -> Bool {
        let compiled = try ExpressionEvaluator.compile(source, runtimeLimits: limits)
        return try ExpressionEvaluator.evaluate(compiled, context: context, locale: locale ?? english,
                                                runtimeLimits: limits, phoneticResolver: resolver)
    }
    private func message(_ source: String, _ context: [ExactString: PlaceholderValue],
                         limits: TranslationRuntimeLimits = .defaults) throws -> String {
        do { _ = try evaluate(source, context, limits: limits) }
        catch let error as TranslationEvaluationError { return error.message }
        throw TestFailure("Expected expression to fail")
    }

    func testCompiledExpressionIsReusableAndBooleanPrecedenceIsPreserved() throws {
        let expression = try ExpressionEvaluator.compile("a == 1 || b == 1 && c == 1")
        func checked<T: Sendable>(_ value: T) -> T { value }
        let compiled = checked(expression)
        XCTAssertTrue(try ExpressionEvaluator.evaluate(compiled, context: ["a": .integer(1), "b": .integer(1), "c": .integer(0)], locale: english))
        XCTAssertFalse(try evaluate("(a == 1 || b == 1) && c == 1", ["a": .integer(1), "b": .integer(1), "c": .integer(0)]))
        XCTAssertTrue(try ExpressionEvaluator.evaluate(compiled, context: ["a": .integer(0), "b": .integer(1), "c": .integer(1)], locale: english))
        XCTAssertFalse(try ExpressionEvaluator.evaluate(compiled, context: ["a": .integer(0), "b": .integer(1), "c": .integer(0)], locale: english))
    }

    func testShortCircuitSkipsMissingNullUnsupportedAndInvalidNumericValues() throws {
        let values: [ExactString: PlaceholderValue] = ["a": .integer(1), "nil": .null, "bool": .boolean(true), "bad": .number(.double(.nan))]
        for right in ["absent == 1", "nil == 1", "bool == 1", "bad == 1"] {
            XCTAssertTrue(try evaluate("a == 1 || (\(right))", values))
            XCTAssertFalse(try evaluate("a == 0 && (\(right))", values))
        }
        XCTAssertEqual(try message("absent == 1 || a == 1", values), "No value was provided for placeholder 'absent'")
        XCTAssertEqual(try message("a == 0 || nil == 1", values), "Placeholder 'nil' resolved to null")
        // Both runtime operand types are inspected before unsupported dispatch.
        XCTAssertEqual(try message("bool == missing", values), "No value was provided for placeholder 'missing'")
    }

    func testAllNumericOperatorsUseExactSignedDecimalComparison() throws {
        let huge = String(repeating: "9", count: 200)
        let values: [ExactString: PlaceholderValue] = ["n": .number(.decimal(try ExactDecimal(huge + ".000000000000000000000000000000000000001")))]
        XCTAssertTrue(try evaluate("n > \(huge)", values))
        XCTAssertTrue(try evaluate("n < \(huge).000000000000000000000000000000000000002", values))
        XCTAssertTrue(try evaluate("n != \(huge)", values))
        XCTAssertTrue(try evaluate("-1.00 == -1 && -1 <= 0 && 0 >= -1 && -0.0 == 0 && 1.00 != 2"))
        XCTAssertTrue(try evaluate("1e100 > 9e99 && 1e100 == 10e99"))
        XCTAssertTrue(try evaluate("f < d", ["f": .number(.float(Float(bitPattern: 0x3f800001))), "d": .number(.double(Double(Float(bitPattern: 0x3f800001))))]))
    }

    func testEveryLanguageFormConstantAndTypedValueUsesItsOwnAxis() throws {
        for form in LanguageFormValue.allCases {
            XCTAssertTrue(try evaluate("value == \(form.rawValue)", ["value": .languageForm(form)]), form.rawValue)
            XCTAssertFalse(try evaluate("value != \(form.rawValue)", ["value": .languageForm(form)]), form.rawValue)
            XCTAssertTrue(try evaluate("\(form.rawValue) == \(form.rawValue)"), form.rawValue)
        }
        XCTAssertEqual(try message("a == b", ["a": .languageForm(.gender(.feminine)), "b": .languageForm(.grammaticalCase(.dative))]),
                       "Unable to evaluate expression 'a == b'. Operand runtime types Gender and GrammaticalCase are incompatible")
    }

    func testRuntimeOrderingRejectsEveryNominalAxis() throws {
        let values: [(LanguageFormValue, String)] = [(.gender(.feminine), "gender"), (.grammaticalCase(.dative), "grammatical case"),
            (.definiteness(.definite), "definiteness"), (.classifier(.person), "classifier"), (.formality(.formal), "formality"),
            (.clusivity(.inclusive), "clusivity"), (.animacy(.animate), "animacy"), (.cardinality(.one), "cardinality"),
            (.ordinality(.one), "ordinality"), (.phonetic(.vowel), "phonetic")]
        for (form, noun) in values {
            XCTAssertEqual(try message("a > b", ["a": .languageForm(form), "b": .languageForm(form)]),
                           "You may only use the '==' and '!=' operators when performing \(noun) comparisons. Offending comparison: 'a > b'")
        }
    }

    func testPluralClassificationUsesSupplyingLocaleAndVisibleScale() throws {
        XCTAssertTrue(try evaluate("n == CARDINALITY_ONE", ["n": .integer(1)], locale: LocaleTag("en")))
        XCTAssertTrue(try evaluate("n == CARDINALITY_OTHER", ["n": .number(.decimal(ExactDecimal("1.0")))], locale: LocaleTag("en")))
        XCTAssertTrue(try evaluate("1 == CARDINALITY_ONE && 1.0 == CARDINALITY_OTHER", locale: LocaleTag("en")))
        XCTAssertTrue(try evaluate("n == ORDINALITY_ONE", ["n": .integer(21)], locale: LocaleTag("en")))
        XCTAssertTrue(try evaluate("n == ORDINALITY_OTHER", ["n": .integer(11)], locale: LocaleTag("en")))
        XCTAssertTrue(try evaluate("n == CARDINALITY_FEW", ["n": .integer(2)], locale: LocaleTag("ru")))
        XCTAssertTrue(try evaluate("n == CARDINALITY_OTHER", ["n": .number(.decimal(ExactDecimal("2.0")))], locale: LocaleTag("ru")))
        XCTAssertTrue(try evaluate("n == CARDINALITY_ONE && n < 0", ["n": .integer(-1)]))
    }

    func testCompactOperandsSeparateSourceComparisonFromExpandedClassification() throws {
        let compact = try PluralOperands.forNumber(ExactDecimal("-1.0"), compactExponent: 6)
        XCTAssertTrue(try evaluate("p == -1 && p != -1000000 && p == CARDINALITY_MANY", ["p": .pluralOperands(compact)], locale: LocaleTag("fr")))
        let explicit = try PluralOperands.forNumber(1, visibleDecimalPlaces: 1)
        XCTAssertTrue(try evaluate("p == 1 && p == CARDINALITY_OTHER", ["p": .pluralOperands(explicit)]))
    }

    func testRuntimeLimitsRevalidateOperandsWithCorrectFailurePriorityAndCauses() throws {
        let lower = try TranslationRuntimeLimits(maximumNumberPrecision: 1, maximumVisibleDecimalPlaces: 0, maximumCompactExponent: 0)
        let source = try PluralOperands.forNumber(ExactDecimal("12.00"), visibleDecimalPlaces: 2, compactExponent: 1)
        XCTAssertEqual(try message("p == 1", ["p": .pluralOperands(source)], limits: lower),
                       "Unable to extract numeric value from 'p': Plural operands value 'p' precision 4 exceeds the maximum of 1")
        let metadata = try PluralOperands.forNumber(1, visibleDecimalPlaces: 2, compactExponent: 1)
        XCTAssertEqual(try message("p == 1", ["p": .pluralOperands(metadata)], limits: lower),
                       "Unable to extract numeric value from 'p': Plural operands compact exponent 1 exceeds the maximum of 0")
        let visible = try PluralOperands.forNumber(1, visibleDecimalPlaces: 1)
        XCTAssertEqual(try message("p == 1", ["p": .pluralOperands(visible)], limits: lower),
                       "Unable to extract numeric value from 'p': Plural operands visible decimal places 1 exceeds the maximum of 0")
        let largeInteger = String(repeating: "9", count: 5_000)
        XCTAssertEqual(try message("n == 1", ["n": .number(.bigInteger(largeInteger))], limits: lower),
                       "Unable to extract numeric value from 'n': Numeric value 'n' precision 5000 exceeds the maximum of 1")
        do { _ = try evaluate("n == 1", ["n": .number(.decimal(ExactDecimal("1.00")))], limits: lower); XCTFail("Expected active precision refusal") }
        catch let error as TranslationEvaluationError {
            XCTAssertEqual(error.kind, .expression)
            XCTAssertEqual((error.cause as? NumericError)?.kind, .invalidArgument)
            XCTAssertEqual((error.cause as? NumericError)?.message, "Numeric value 'n' precision 3 exceeds the maximum of 1")
        }
    }

    func testRawTextHasNoTextualEqualityOrderingOrNumericCoercion() throws {
        let values: [ExactString: PlaceholderValue] = ["a": .text("book"), "b": .text("book"), "n": .integer(1)]
        XCTAssertEqual(try message("a == b", values), "Raw CharSequence placeholders 'a' and 'b' cannot be compared with '==': expressions do not support textual equality. Compare phonetic input with a PHONETIC_* constant or an explicit Phonetic value instead")
        XCTAssertEqual(try message("a < b", values), "Raw CharSequence placeholders 'a' and 'b' cannot be compared with '<': expressions do not support textual ordering. Use numeric operands for ordering, or compare phonetic input with a PHONETIC_* constant or an explicit Phonetic value using '==' or '!='")
        XCTAssertEqual(try message("n == a", values), "Numeric comparison 'n == a' requires numeric operands supplied as Number or PluralOperands values, but placeholder 'a' resolved to String")
        XCTAssertEqual(try message("a > n", values), "Numeric comparison 'a > n' requires numeric operands supplied as Number or PluralOperands values, but placeholder 'a' resolved to String")
    }

    func testPhoneticCallbacksAreOrderedRepeatableAndPreserveThrownIdentity() throws {
        let log = CallLog()
        let resolver: PhoneticResolver = { term, locale in log.append(term, locale); return .vowel }
        XCTAssertTrue(try evaluate("a == PHONETIC_VOWEL && a == PHONETIC_VOWEL", ["a": .text("é")], locale: LocaleTag("mo-MD"), resolver: resolver))
        XCTAssertEqual(log.calls.map(\.0), ["é", "é"])
        XCTAssertEqual(log.calls.map { $0.1.tag }, ["mo-MD", "mo-MD"])
        XCTAssertTrue(try evaluate("p == PHONETIC_VOWEL", ["p": .languageForm(.phonetic(.vowel))], resolver: resolver))
        XCTAssertEqual(log.calls.count, 2)
        XCTAssertTrue(try evaluate("1 == 1 || a == PHONETIC_VOWEL", ["a": .text("apple")], resolver: resolver))
        XCTAssertEqual(log.calls.count, 2)
        let original = TestFailure("resolver failed")
        do { _ = try evaluate("a == PHONETIC_VOWEL", ["a": .text("apple")], resolver: { _, _ in throw original }); XCTFail("Expected resolver error") }
        catch { XCTAssertTrue((error as? TestFailure) === original) }
    }

    func testRawLanguageFormSpellingIsStillPhoneticAndDispatchOrderIsObservable() throws {
        let log = CallLog()
        let resolver: PhoneticResolver = { term, locale in log.append(term, locale); return .vowel }
        do { _ = try evaluate("a == GENDER_FEMININE", ["a": .text("GENDER_FEMININE")], resolver: resolver); XCTFail("Expected unsupported extraction") }
        catch let error as TranslationEvaluationError { XCTAssertEqual(error.message, "Unable to extract Phonetic value from 'GENDER_FEMININE'") }
        XCTAssertEqual(log.calls.map(\.0), ["GENDER_FEMININE"])
        do { _ = try evaluate("GENDER_FEMININE == a", ["a": .text("GENDER_FEMININE")], resolver: resolver); XCTFail("Expected unsupported extraction") }
        catch let error as TranslationEvaluationError { XCTAssertEqual(error.message, "Unable to extract Phonetic value from 'GENDER_FEMININE'") }
        XCTAssertEqual(log.calls.count, 1)
        XCTAssertEqual(try message("c == GENDER_FEMININE", ["c": .languageForm(.cardinality(.one))]), "Unable to extract Cardinality value from 'GENDER_FEMININE'")
    }

    func testPhoneticInputBudgetCountsUTF16AndRetainsArgumentCause() throws {
        let log = CallLog(), limits = try TranslationRuntimeLimits(maximumInterpolatedOutputCharacters: 1)
        do { _ = try evaluate("a == PHONETIC_VOWEL", ["a": .text("😀")], limits: limits, resolver: { term, locale in log.append(term, locale); return .vowel }); XCTFail("Expected input length refusal") }
        catch let error as TranslationEvaluationError {
            XCTAssertEqual(error.kind, .expression)
            XCTAssertEqual(error.message, "Phonetic input for placeholder 'a' exceeds the maximum of 1 characters")
            XCTAssertEqual((error.cause as? TranslationEvaluationError)?.kind, .invalidArgument)
        }
        XCTAssertEqual(log.calls.count, 0)
        do { _ = try evaluate("a == PHONETIC_VOWEL", ["a": .text("a")]); XCTFail("Expected default resolver refusal") }
        catch let error as TranslationEvaluationError { XCTAssertEqual(error.kind, .invalidState) }
    }

    func testExactUnicodeVariableLookupAndUnsupportedCustomValueAreNeverRendered() throws {
        XCTAssertTrue(try evaluate("é == 1 && e\u{301} == 2", [ExactString("é"): .integer(1), ExactString("e\u{301}"): .integer(2)]))
        let custom = UnrenderedValue()
        XCTAssertEqual(try message("x == 1", ["x": .custom(custom)]), "Unable to evaluate expression 'x == 1'. Operand types UNKNOWN and NUMBER are unsupported")
        XCTAssertEqual(try message("x == 1", ["x": .boolean(true)]), "Unable to evaluate expression 'x == 1'. Operand types UNKNOWN and NUMBER are unsupported")
    }

    func testCompilationIsEagerAndRetainsRealCategoryCauses() throws {
        XCTAssertThrowsError(try ExpressionEvaluator.compile("1 == 1 || missing =="))
        let length = try TranslationRuntimeLimits(maximumExpressionCharacters: 3)
        do { _ = try ExpressionEvaluator.compile("1 == 1", runtimeLimits: length); XCTFail("Expected length refusal") }
        catch let error as TranslationEvaluationError { XCTAssertEqual(error.kind, .expression); XCTAssertNil(error.cause) }
        do { _ = try ExpressionEvaluator.compile("1 < 2 < 3"); XCTFail("Expected chained comparison refusal") }
        catch let error as TranslationEvaluationError {
            XCTAssertTrue(error.message.hasPrefix("Invalid expression '1 < 2 < 3': Chained comparisons"))
            XCTAssertEqual((error.cause as? TranslationEvaluationError)?.kind, .expression)
            XCTAssertNil((error.cause as? TranslationEvaluationError)?.cause)
        }
        do { _ = try ExpressionEvaluator.compile("n == 1e1025"); XCTFail("Expected eager scale refusal") }
        catch let error as TranslationEvaluationError { XCTAssertEqual((error.cause as? NumericError)?.kind, .invalidArgument) }
        // Later bad lexical input wins over an earlier invalid numeric literal.
        do { _ = try ExpressionEvaluator.compile("n == 1e1025\u{A0}"); XCTFail("Expected lexical refusal") }
        catch let error as TranslationEvaluationError { XCTAssertTrue(error.message.hasPrefix("Unexpected code point U+00A0")); XCTAssertNil(error.cause) }
    }

    func testLargestFlatBooleanTreeUsesNoRecursiveEvaluation() throws {
        let limits = try TranslationRuntimeLimits(maximumExpressionCharacters: 4_096, maximumExpressionTokens: 512, maximumExpressionNestingDepth: 0)
        let source = Array(repeating: "0 == 0", count: 128).joined(separator: " && ")
        XCTAssertTrue(try evaluate(source, limits: limits))
        XCTAssertThrowsError(try ExpressionEvaluator.compile(source + " && 0 == 0", runtimeLimits: limits))
    }

    private final class TestFailure: Error { let message: String; init(_ message: String) { self.message = message } }
    private struct UnrenderedValue: PlaceholderConvertible {
        func lokalizedDescription(maximumCharacters: Int?) throws -> String { throw TestFailure("Custom conversion must not run") }
    }
    private final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(String, LocaleTag)] = []
        var calls: [(String, LocaleTag)] { lock.lock(); defer { lock.unlock() }; return values }
        func append(_ term: String, _ locale: LocaleTag) { lock.lock(); defer { lock.unlock() }; values.append((term, locale)) }
    }
}
