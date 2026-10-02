import Lokalized

/// Native M2 numeric qualification, independent of XCTest and reference JSON.
enum NumericQualification {
    static func run() throws -> Int {
        var checks = 0
        func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { throw ConformanceError("Numeric qualification: \(message)") }
            checks += 1
        }
        func refuse(_ kind: NumericError.Kind, _ message: String, _ body: () throws -> Void) throws {
            do { try body() }
            catch let error as NumericError {
                try expect(error.kind == kind && error.message == message, "refusal kind and diagnostic: \(message)")
                return
            }
            throw ConformanceError("Numeric qualification accepted invalid input: \(message)")
        }

        let one = try ExactDecimal("1")
        let oneZero = try ExactDecimal("1.0")
        let oneTwoZeroes = try ExactDecimal("+001.00")
        try expect(one.compare(to: oneTwoZeroes) == 0, "numerical equality ignores written scale")
        try expect(Set([one, oneZero, oneTwoZeroes]).count == 3, "representation equality retains written scale")
        try expect(oneTwoZeroes.coefficient == "100" && oneTwoZeroes.precision == 3 && oneTwoZeroes.scale == 2,
                   "significant trailing zeroes in decimal coefficient")
        try expect(oneTwoZeroes.plainString == "1.00", "plain decimal rendering retains written zeroes")
        try expect(try ExactDecimal("-0.00") == ExactDecimal("0.00"), "decimal zero normalizes source sign")
        try expect(try ExactDecimal("1e100").compare(to: ExactDecimal("9e99")) == 1, "large comparison avoids binary arithmetic")
        let hundredNines = String(repeating: "9", count: 100)
        try expect(try ExactDecimal(hundredNines + ".0000000000000000000000000000000000000001")
                    .compare(to: ExactDecimal(hundredNines + ".0000000000000000000000000000000000000002")) == -1,
                   "comparison exceeds Foundation decimal precision")
        try expect(try ExactDecimal("0.000001").description == "0.000001", "BigDecimal plain-render threshold")
        try expect(try ExactDecimal("0.0000001").description == "1E-7", "BigDecimal scientific-render threshold")
        try expect(try ExactDecimal("1.20E+4").description == "1.20E+4", "negative scale scientific rendering")
        try expect(try ExactDecimal("0E+3").plainString == "0", "negative-scale zero plain rendering")
        try expect(try ExactDecimal("1e000000000000000000000002").plainString == "100", "leading exponent zeroes")
        try expect(try ExactDecimal("-123.4500").remainder(dividingBy: 10).plainString == "-3.4500",
                   "remainder retains fractional scale and source sign")
        try expect(try ExactDecimal("12E+3").remainder(dividingBy: 7).plainString == "2", "negative-scale remainder")
        try expect(try ExactDecimal("0E+3").remainder(dividingBy: 7).scale == 0,
                   "negative-scale remainder uses the documented scale-zero normalization")
        try expect(try ExactDecimal(String(repeating: "9", count: 1_000)).remainder(dividingBy: 100).plainString == "99",
                   "bounded exact large integer remainder")
        try expect(try ExactDecimal("1.000").isIntegerValued && !ExactDecimal("1.001").isIntegerValued,
                   "integer membership ignores trailing zeroes")

        let natural = try PluralOperands.forNumber(ExactDecimal("-12.03400"))
        try expect(natural.n.plainString == "12.03400" && natural.i.plainString == "12", "absolute n and integral i")
        try expect(natural.v == 5 && natural.w == 3, "visible and stripped decimal place counts")
        try expect(natural.f.plainString == "3400" && natural.t.plainString == "34", "visible and stripped fractional integers")
        try expect(natural.sourceNumber.plainString == "-12.03400" && natural.explicitVisibleDecimalPlaces == nil,
                   "signed source is separate from natural operands")
        let compact = try PluralOperands.forNumber(ExactDecimal("-1.2300"), compactExponent: 2)
        try expect(compact.n.plainString == "123.00" && compact.sourceNumber.plainString == "-1.2300",
                   "compact mantissa expansion preserves unexpanded signed source")
        try expect(compact.v == 2 && compact.w == 0 && compact.c == 2 && compact.e == 2,
                   "compact expansion happens before fraction operands")
        try expect(try PluralOperands.forNumber(1, compactExponent: 6).number.plainString == "1000000",
                   "compact 1M expands exactly")
        try expect(try PluralOperands.forNumber(ExactDecimal("1E+3")).number.scale == 0,
                   "zero compact shift clamps negative scale")
        let reduced = try PluralOperands.forNumber(ExactDecimal("1.2300"), visibleDecimalPlaces: 2)
        try expect(reduced.n.plainString == "1.23" && reduced.sourceNumber.plainString == "1.2300",
                   "explicit scale reduction preserves source")
        try expect(reduced.explicitVisibleDecimalPlaces == 2, "explicit visible count survives construction")
        try expect(try PluralOperands.forNumber(7, visibleDecimalPlaces: 3).n.plainString == "7.000",
                   "explicit visible count adds exact zeroes")
        try refuse(.roundingNecessary, "Rounding necessary") {
            _ = try PluralOperands.forNumber(ExactDecimal("1.001"), visibleDecimalPlaces: 2)
        }
        let ordinary = try PluralOperands.forNumber(1)
        let sourceRounded = try PluralOperands.forNumber(ExactDecimal("1.000"), visibleDecimalPlaces: 0)
        try expect(ordinary == sourceRounded && ordinary.hashValue == sourceRounded.hashValue,
                   "operand equality follows n, source sign and compact exponent")
        try expect(try ordinary != PluralOperands.forNumber(-1), "operand equality includes source sign")
        try expect(try ordinary != PluralOperands.forNumber(ExactDecimal("1.0")), "operand equality includes n scale")
        try expect(try PluralOperands.forNumber(1_000_000) != PluralOperands.forNumber(1, compactExponent: 6),
                   "operand equality includes compact exponent")

        let precisionOne = try TranslationRuntimeLimits(maximumNumberPrecision: 1, maximumAbsoluteNumberScale: 8)
        try expect(try PluralOperands(.integer(1_000_000), runtimeLimits: precisionOne).n.plainString == "1000000",
                   "boxed integral normalization precedes precision validation")
        try refuse(.invalidArgument, "Number precision 7 exceeds the maximum of 1") {
            _ = try PluralOperands(.bigInteger("1000000"), runtimeLimits: precisionOne)
        }
        try expect(try PluralOperands.forNumber(UInt64.max).n.plainString == "18446744073709551615", "unsigned native integer conversion")
        try expect(try PluralOperands.forNumber(Int64.min).sourceNumber.plainString == "-9223372036854775808", "minimum signed integer conversion")
        try expect(try NumericValue.forBigInteger("+000123").description == "123", "big integer factory canonicalizes leading zeroes")
        try refuse(.invalidDecimal, "Invalid integer text '1.0'") { _ = try NumericValue.forBigInteger("1.0") }
        try refuse(.invalidArgument, "Compact exponent must be non-negative, but was -1") {
            _ = try PluralOperands(.double(.nan), visibleDecimalPlaces: -1, compactExponent: -1)
        }
        try refuse(.invalidArgument, "Visible decimal places must be non-negative, but was -1") {
            _ = try PluralOperands(.double(.nan), visibleDecimalPlaces: -1)
        }
        try refuse(.invalidArgument, "Number must be finite, but was Infinity") { _ = try PluralOperands(.float(.infinity)) }
        try refuse(.invalidArgument, "Number scale 1025 exceeds the maximum absolute scale of 1024") {
            _ = try ExactDecimal(String(repeating: "9", count: 1025) + "e-1025")
        }
        let raised = try TranslationRuntimeLimits(maximumNumberPrecision: 4096, maximumAbsoluteNumberScale: 4096,
                                                 maximumVisibleDecimalPlaces: 4096, maximumCompactExponent: 4096)
        let large = try ExactDecimal(String(repeating: "9", count: 4096), runtimeLimits: raised)
        try expect(try PluralOperands.forNumber(large, runtimeLimits: raised).n.precision == 4096, "hard source precision ceiling is usable")
        try refuse(.invalidArgument, "Number precision 4096 exceeds the maximum of 1024") { _ = try PluralOperands.forNumber(large) }
        try refuse(.invalidArgument, "Number scale 4097 exceeds the maximum absolute scale of 4096") {
            _ = try ExactDecimal("1e-4097", runtimeLimits: raised)
        }
        let materializedInput = try ExactDecimal(String(repeating: "9", count: 4096) + "e4096", runtimeLimits: raised)
        let materialized = try PluralOperands.forNumber(materializedInput, visibleDecimalPlaces: 4096, compactExponent: 4096,
                                                      runtimeLimits: raised)
        try expect(materialized.n.precision == 12288 && materialized.n.scale == 0, "hard materialized precision remains exact")
        let float = Float(bitPattern: 0x3f800001)
        try expect(NumericValue.float(float).description == "1.0000001", "binary32 pinned rendering")
        try expect(NumericValue.double(Double(float)).description == "1.0000001192092896", "binary64 retains its distinct decimal")
        try expect(try PluralOperands.forNumber(Float.leastNonzeroMagnitude).sourceNumber.description == "1.4E-45", "binary32 subnormal conversion")
        try expect(try PluralOperands.forNumber(Double.leastNonzeroMagnitude).sourceNumber.description == "4.9E-324", "binary64 subnormal conversion")
        try expect(NumericValue.double(-0.0).description == "-0.0", "float rendering retains signed zero")
        try expect(try PluralOperands.forNumber(-0.0 as Double) == PluralOperands.forNumber(0.0 as Double), "plural operands normalize signed zero")
        return checks
    }
}
