import XCTest
import Lokalized

final class NumericTests: XCTestCase {
    private func error(_ body: () throws -> Void, kind: NumericError.Kind, message: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { failure in
            guard let numeric = failure as? NumericError else {
                return XCTFail("Expected NumericError, got \(failure)", file: file, line: line)
            }
            XCTAssertEqual(numeric.kind, kind, file: file, line: line)
            XCTAssertEqual(numeric.message, message, file: file, line: line)
        }
    }

    func testDecimalRepresentationAndNumericalComparisonAreSeparate() throws {
        let one = try ExactDecimal("1")
        let onePointZero = try ExactDecimal("1.0")
        let onePointZeroZero = try ExactDecimal("+001.00")
        XCTAssertEqual(onePointZeroZero.coefficient, "100")
        XCTAssertEqual(onePointZeroZero.scale, 2)
        XCTAssertEqual(onePointZeroZero.precision, 3)
        XCTAssertEqual(onePointZeroZero.plainString, "1.00")
        XCTAssertEqual(one.compare(to: onePointZeroZero), 0)
        XCTAssertEqual(Set([one, onePointZero, onePointZeroZero]).count, 3)
        XCTAssertEqual(try ExactDecimal("-0.00"), try ExactDecimal("0.00"))
        XCTAssertEqual(try ExactDecimal("-0.00").signum, 0)
        XCTAssertEqual(try ExactDecimal("-0.00").precision, 1)
    }

    func testStrictDecimalGrammarAndExponentFailures() throws {
        for text in ["", "+", ".", " 1", "1 ", "1,5", "NaN", "Infinity", "0x10", "1e", "--1", "١"] {
            error({ _ = try ExactDecimal(text) }, kind: .invalidDecimal, message: "Invalid decimal text '\(text)'")
        }
        XCTAssertEqual(try ExactDecimal(".125").plainString, "0.125")
        XCTAssertEqual(try ExactDecimal("1.").plainString, "1")
        XCTAssertEqual(try ExactDecimal("01.20e+2").plainString, "120")
        XCTAssertEqual(try ExactDecimal("1e0000000000000000000000000000000002").plainString, "100")
        error({ _ = try ExactDecimal("1e10000000000") }, kind: .invalidDecimal, message: "Too many nonzero exponent digits.")
        error({ _ = try ExactDecimal("1e2147483648") }, kind: .invalidDecimal, message: "Exponent overflow.")
        error({ _ = try ExactDecimal("1e-2147483648") }, kind: .invalidDecimal, message: "Exponent overflow.")
    }

    func testScientificAndPlainRenderingMatchBigDecimalThresholds() throws {
        let cases: [(String, String, String)] = [
            ("0.000001", "0.000001", "0.000001"),
            ("0.0000001", "1E-7", "0.0000001"),
            ("1.20E+4", "1.20E+4", "12000"),
            ("0E+3", "0E+3", "0"),
            ("0.0000000", "0E-7", "0.0000000"),
            ("-123E-10", "-1.23E-8", "-0.0000000123"),
            ("-10.00", "-10.00", "-10.00")
        ]
        for (input, canonical, plain) in cases {
            let decimal = try ExactDecimal(input)
            XCTAssertEqual(decimal.description, canonical)
            XCTAssertEqual(decimal.plainString, plain)
        }
    }

    func testComparisonIsExactBeyondFoundationPrecision() throws {
        let prefix = String(repeating: "9", count: 100)
        let low = try ExactDecimal(prefix + ".1000000000000000000000000000000000000001")
        let high = try ExactDecimal(prefix + ".1000000000000000000000000000000000000002")
        XCTAssertEqual(low.compare(to: high), -1)
        XCTAssertEqual(high.compare(to: low), 1)
        XCTAssertEqual(try ExactDecimal("-" + prefix).compare(to: ExactDecimal("-1")), -1)
        XCTAssertEqual(try ExactDecimal("1e100").compare(to: ExactDecimal("1e99")), 1)
        XCTAssertEqual(try ExactDecimal("1.0000").compare(to: ExactDecimal("1")), 0)
        XCTAssertEqual(try ExactDecimal("-0e100").compare(to: ExactDecimal("0.000")), 0)
    }

    func testRemainderRetainsScaleFractionAndSign() throws {
        let cases: [(String, Int, String, Int)] = [
            ("123.4500", 10, "3.4500", 4), ("-123.4500", 10, "-3.4500", 4),
            ("100.00", 10, "0.00", 2), ("0.00120", 100, "0.00120", 5),
            ("12E+3", 7, "2", 0), ("-12E+3", 7, "-2", 0),
            ("1.20", 1, "0.20", 2)
        ]
        for (input, divisor, result, scale) in cases {
            let remainder = try ExactDecimal(input).remainder(dividingBy: divisor)
            XCTAssertEqual(remainder.plainString, result)
            XCTAssertEqual(remainder.scale, scale)
        }
        let thousandNines = try ExactDecimal(String(repeating: "9", count: 1_000))
        XCTAssertEqual(try thousandNines.remainder(dividingBy: 100).plainString, "99")
        XCTAssertEqual(try ExactDecimal("9223372036854775807").remainder(dividingBy: Int.max / 10).plainString, "7")
        XCTAssertFalse(try ExactDecimal("1.001").isIntegerValued)
        XCTAssertTrue(try ExactDecimal("1.000").isIntegerValued)
        XCTAssertTrue(try ExactDecimal("0e-1024").isIntegerValued)
        XCTAssertTrue(try ExactDecimal("1e1024").isIntegerValued)
        for divisor in [0, -1, Int.max] {
            error({ _ = try ExactDecimal("1").remainder(dividingBy: divisor) }, kind: .invalidArgument,
                  message: "Modulus must be positive and no greater than \(Int.max / 10), but was \(divisor)")
        }
    }

    func testNaturalDecimalOperandsRetainVisibleZeroes() throws {
        let operands = try PluralOperands.forNumber(ExactDecimal("-12.03400"))
        XCTAssertEqual(operands.number.plainString, "12.03400")
        XCTAssertEqual(operands.i.plainString, "12")
        XCTAssertEqual(operands.v, 5)
        XCTAssertEqual(operands.w, 3)
        XCTAssertEqual(operands.f.plainString, "3400")
        XCTAssertEqual(operands.t.plainString, "34")
        XCTAssertEqual(operands.c, 0)
        XCTAssertEqual(operands.e, 0)
        XCTAssertEqual(operands.sourceNumber.plainString, "-12.03400")
        XCTAssertNil(operands.explicitVisibleDecimalPlaces)
        XCTAssertEqual(operands.description, "PluralOperands{number=12.03400, compactExponent=0}")
    }

    func testCompactInputIsMantissaAndSourceNumberRemainsSigned() throws {
        let operands = try PluralOperands(.decimal(ExactDecimal("-1.2300")), compactExponent: 2)
        XCTAssertEqual(operands.n.plainString, "123.00")
        XCTAssertEqual(operands.sourceNumber.plainString, "-1.2300")
        XCTAssertEqual(operands.i.plainString, "123")
        XCTAssertEqual(operands.v, 2)
        XCTAssertEqual(operands.w, 0)
        XCTAssertEqual(operands.f.plainString, "0")
        XCTAssertEqual(operands.t.plainString, "0")
        XCTAssertEqual(operands.c, 2)
        XCTAssertEqual(operands.e, 2)
        XCTAssertEqual(try PluralOperands.forNumber(1, compactExponent: 6).number.plainString, "1000000")
        XCTAssertEqual(try PluralOperands.forNumber(ExactDecimal("1E+3")).number.scale, 0)
        XCTAssertEqual(try PluralOperands.forNumber(ExactDecimal("0E+3")).number.scale, 0)
    }

    func testExplicitVisibleScaleNeverRounds() throws {
        let reduced = try PluralOperands.forNumber(ExactDecimal("-1.2300"), visibleDecimalPlaces: 2)
        XCTAssertEqual(reduced.number.plainString, "1.23")
        XCTAssertEqual(reduced.sourceNumber.plainString, "-1.2300")
        XCTAssertEqual(reduced.explicitVisibleDecimalPlaces, 2)
        XCTAssertEqual(try PluralOperands.forNumber(7, visibleDecimalPlaces: 3).number.plainString, "7.000")
        XCTAssertEqual(try PluralOperands.forNumber(ExactDecimal("0.000"), visibleDecimalPlaces: 0).number.plainString, "0")
        error({ _ = try PluralOperands.forNumber(ExactDecimal("1.001"), visibleDecimalPlaces: 2) },
              kind: .roundingNecessary, message: "Rounding necessary")
    }

    func testOperandsEqualityIncludesScaleSourceSignAndExponent() throws {
        let one = try PluralOperands.forNumber(ExactDecimal("1"))
        let oneZero = try PluralOperands.forNumber(ExactDecimal("1.0"))
        let negative = try PluralOperands.forNumber(ExactDecimal("-1"))
        XCTAssertNotEqual(one, oneZero)
        XCTAssertNotEqual(one, negative)
        XCTAssertEqual(Set([one, oneZero, negative]).count, 3)
        let explicit = try PluralOperands.forNumber(ExactDecimal("1.000"), visibleDecimalPlaces: 0)
        XCTAssertEqual(one, explicit)
        XCTAssertEqual(one.hashValue, explicit.hashValue)
        XCTAssertEqual(try PluralOperands.forNumber(ExactDecimal("-0.00")), try PluralOperands.forNumber(ExactDecimal("0.00")))
        let million = try PluralOperands.forNumber(1_000_000)
        let compact = try PluralOperands.forNumber(1, compactExponent: 6)
        XCTAssertEqual(million.number, compact.number)
        XCTAssertNotEqual(million, compact)
    }

    func testBoxedIntegerAndBigIntegerLimitsPreserveJavaDistinction() throws {
        let limits = try TranslationRuntimeLimits(maximumNumberPrecision: 1, maximumAbsoluteNumberScale: 8)
        XCTAssertEqual(try PluralOperands.forNumber(1_000_000, runtimeLimits: limits).number.plainString, "1000000")
        error({ _ = try PluralOperands(.bigInteger("1000000"), runtimeLimits: limits) },
              kind: .invalidArgument, message: "Number precision 7 exceeds the maximum of 1")
        let unsigned = try PluralOperands.forNumber(UInt64.max)
        XCTAssertEqual(unsigned.number.plainString, "18446744073709551615")
        XCTAssertEqual(try PluralOperands.forNumber(Int64.min).sourceNumber.plainString, "-9223372036854775808")
        XCTAssertEqual(try NumericValue.forBigInteger("+000123").description, "123")
        XCTAssertEqual(NumericValue.bigInteger("+000123").description, "123")
        error({ _ = try NumericValue.forBigInteger("1.0") }, kind: .invalidDecimal, message: "Invalid integer text '1.0'")
    }

    func testOperandOptionFailurePrecedenceBeforeConversion() throws {
        error({ _ = try PluralOperands(.double(.nan), visibleDecimalPlaces: -1, compactExponent: -1) },
              kind: .invalidArgument, message: "Compact exponent must be non-negative, but was -1")
        error({ _ = try PluralOperands(.double(.nan), visibleDecimalPlaces: -1) },
              kind: .invalidArgument, message: "Visible decimal places must be non-negative, but was -1")
        error({ _ = try PluralOperands(.double(.nan), compactExponent: 65) },
              kind: .invalidArgument, message: "Compact exponent 65 exceeds the maximum of 64")
        error({ _ = try PluralOperands(.double(.nan), visibleDecimalPlaces: 1025) },
              kind: .invalidArgument, message: "Visible decimal places 1025 exceeds the maximum of 1024")
        error({ _ = try PluralOperands(.float(.infinity)) }, kind: .invalidArgument, message: "Number must be finite, but was Infinity")
        error({ _ = try PluralOperands(.double(-.infinity)) }, kind: .invalidArgument, message: "Number must be finite, but was -Infinity")
        error({ _ = try PluralOperands(.double(.nan)) }, kind: .invalidArgument, message: "Number must be finite, but was NaN")
    }

    func testNumericLimitOrderingRaisedConstructionAndRevalidation() throws {
        error({ _ = try ExactDecimal(String(repeating: "9", count: 1025) + "e-1025") },
              kind: .invalidArgument, message: "Number scale 1025 exceeds the maximum absolute scale of 1024")
        error({ _ = try ExactDecimal(String(repeating: "9", count: 1025)) },
              kind: .invalidArgument, message: "Number precision 1025 exceeds the maximum of 1024")
        let raised = try TranslationRuntimeLimits(maximumNumberPrecision: 4096, maximumAbsoluteNumberScale: 4096,
                                                 maximumVisibleDecimalPlaces: 4096, maximumCompactExponent: 4096)
        let large = try ExactDecimal(String(repeating: "9", count: 4096), runtimeLimits: raised)
        XCTAssertEqual(try PluralOperands.forNumber(large, runtimeLimits: raised).number.precision, 4096)
        error({ _ = try PluralOperands.forNumber(large) }, kind: .invalidArgument, message: "Number precision 4096 exceeds the maximum of 1024")
        let hugeScale = try ExactDecimal("1e-4096", runtimeLimits: raised)
        XCTAssertEqual(try PluralOperands.forNumber(hugeScale, runtimeLimits: raised).v, 4096)
        error({ _ = try PluralOperands.forNumber(hugeScale) }, kind: .invalidArgument,
              message: "Number scale 4096 exceeds the maximum absolute scale of 1024")
        error({ _ = try ExactDecimal("1e-4097", runtimeLimits: raised) }, kind: .invalidArgument,
              message: "Number scale 4097 exceeds the maximum absolute scale of 4096")
        error({ _ = try ExactDecimal(String(repeating: "9", count: 4097), runtimeLimits: raised) },
              kind: .invalidArgument, message: "Number precision 4097 exceeds the maximum of 4096")
    }

    func testHardMaterializedPrecisionAndZeroDoNotEscapeBudgets() throws {
        let raised = try TranslationRuntimeLimits(maximumNumberPrecision: 4096, maximumAbsoluteNumberScale: 4096,
                                                 maximumVisibleDecimalPlaces: 4096, maximumCompactExponent: 4096)
        let input = try ExactDecimal(String(repeating: "9", count: 4096) + "e4096", runtimeLimits: raised)
        let operands = try PluralOperands.forNumber(input, visibleDecimalPlaces: 4096, compactExponent: 4096, runtimeLimits: raised)
        XCTAssertEqual(operands.number.precision, 12288)
        XCTAssertEqual(operands.number.scale, 0)
        XCTAssertEqual(operands.i, operands.number)
        let zero = try PluralOperands.forNumber(ExactDecimal("0e-4096", runtimeLimits: raised), runtimeLimits: raised)
        XCTAssertEqual(zero.v, 4096)
        XCTAssertEqual(zero.w, 0)
        XCTAssertEqual(zero.f.plainString, "0")
    }

    func testPinnedFloatAndDoubleRetainWidthAndCanonicalDecimalSemantics() throws {
        let float = Float(bitPattern: 0x3f800001)
        let double = Double(float)
        XCTAssertEqual(NumericValue.float(float).description, "1.0000001")
        XCTAssertEqual(NumericValue.double(double).description, "1.0000001192092896")
        XCTAssertEqual(try PluralOperands.forNumber(float).sourceNumber.plainString, "1.0000001")
        XCTAssertEqual(try PluralOperands.forNumber(double).sourceNumber.plainString, "1.0000001192092896")
        XCTAssertEqual(try PluralOperands.forNumber(Float.leastNonzeroMagnitude).sourceNumber.description, "1.4E-45")
        XCTAssertEqual(try PluralOperands.forNumber(Double.leastNonzeroMagnitude).sourceNumber.description, "4.9E-324")
        XCTAssertEqual(try PluralOperands.forNumber(-0.0 as Double), try PluralOperands.forNumber(0.0 as Double))
        XCTAssertEqual(NumericValue.double(-0.0).description, "-0.0")
        XCTAssertEqual(try PluralOperands.forNumber(100.0).v, 0)
        XCTAssertEqual(try PluralOperands.forNumber(1.5).v, 1)
        XCTAssertNotEqual(NumericValue.float(.nan), NumericValue.float(Float(bitPattern: 0x7fc00001)))
    }

    func testAllNumericValuesAndOperandsAreSendable() throws {
        func checked<Value: Sendable>(_ value: Value) -> Value { value }
        let decimal = checked(try ExactDecimal("123.00"))
        let value = checked(NumericValue.decimal(decimal))
        let operands = checked(try PluralOperands(value))
        XCTAssertEqual(operands.number.plainString, "123.00")
    }
}
