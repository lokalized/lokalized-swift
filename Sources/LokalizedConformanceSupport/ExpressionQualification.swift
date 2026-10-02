import Foundation
import Lokalized

/// Standalone M4 expression checks: no XCTest, fixtures, expected corpus values,
/// dynamic source execution, or mutable evaluator-wide state.
enum ExpressionQualification {
    static func run() throws -> Int {
        var checks = 0
        let english = try LocaleTag("en")
        func expect(_ condition: @autoclosure () throws -> Bool, _ detail: String) throws {
            guard try condition() else { throw ConformanceError("Expression qualification: \(detail)") }
            checks += 1
        }
        func evaluate(_ source: String, _ context: [ExactString: PlaceholderValue] = [:], locale: LocaleTag? = nil,
                      limits: TranslationRuntimeLimits = .defaults, resolver: PhoneticResolver? = nil) throws -> Bool {
            try ExpressionEvaluator.evaluate(ExpressionEvaluator.compile(source, runtimeLimits: limits), context: context,
                                             locale: locale ?? english, runtimeLimits: limits, phoneticResolver: resolver)
        }
        func refuse(_ source: String, _ context: [ExactString: PlaceholderValue] = [:], kind: TranslationEvaluationError.Kind = .expression,
                    message: String, limits: TranslationRuntimeLimits = .defaults) throws -> TranslationEvaluationError {
            do { _ = try evaluate(source, context, limits: limits); throw ConformanceError("Expected expression refusal") }
            catch let error as TranslationEvaluationError {
                try expect(error.kind == kind && error.message == message, "typed refusal: \(message)")
                return error
            }
        }

        let precedence = try ExpressionEvaluator.compile("a == 1 || b == 1 && c == 1")
        try expect(try ExpressionEvaluator.evaluate(precedence, context: ["a": .integer(1), "b": .integer(1), "c": .integer(0)], locale: english), "AND precedes OR")
        try expect(try !evaluate("(a == 1 || b == 1) && c == 1", ["a": .integer(1), "b": .integer(1), "c": .integer(0)]), "grouping changes precedence")
        try expect(try ExpressionEvaluator.evaluate(precedence, context: ["a": .integer(0), "b": .integer(1), "c": .integer(1)], locale: english), "compiled IR reusable with different context")
        try expect(try !ExpressionEvaluator.evaluate(precedence, context: ["a": .integer(0), "b": .integer(1), "c": .integer(0)], locale: english), "compiled IR has no retained values")
        let values: [ExactString: PlaceholderValue] = ["yes": .integer(1), "nil": .null, "bool": .boolean(true), "nan": .number(.double(.nan))]
        for expression in ["absent == 1", "nil == 1", "bool == 1", "nan == 1"] {
            try expect(try evaluate("yes == 1 || (\(expression))", values), "OR skips \(expression)")
            try expect(try !evaluate("yes == 0 && (\(expression))", values), "AND skips \(expression)")
        }
        _ = try refuse("absent == 1 || yes == 1", values, message: "No value was provided for placeholder 'absent'")
        _ = try refuse("yes == 0 || nil == 1", values, message: "Placeholder 'nil' resolved to null")
        _ = try refuse("bool == absent", values, message: "No value was provided for placeholder 'absent'")
        _ = try refuse("bool == 1", values, message: "Unable to evaluate expression 'bool == 1'. Operand types UNKNOWN and NUMBER are unsupported")

        for source in ["1 == 1.00", "-1 < 0", "-1 <= -1.0", "1 > -1", "1 >= 1.00", "0 != 1", "-0.00 == 0", "1e100 == 10e99", "1e100 > 9e99"] {
            try expect(try evaluate(source), "exact numeric comparison \(source)")
        }
        let large = String(repeating: "9", count: 300)
        try expect(try evaluate("n > \(large)", ["n": .number(.decimal(ExactDecimal(large + ".000000000000000000000000000000000001")))]), "exact digits beyond Foundation precision")
        try expect(try evaluate("n == -9223372036854775808", ["n": .number(.integer(.min))]), "minimum signed native integer")
        try expect(try evaluate("n == 18446744073709551615", ["n": .number(.unsignedInteger(.max))]), "maximum unsigned native integer")
        for value in [PlaceholderValue.byte(-1), .short(-1), .integer(-1), .number(.integer(-1)), .number(.bigInteger("-1")), .number(.float(-1)), .number(.double(-1))] {
            try expect(try evaluate("n == -1", ["n": value]), "supported numeric carrier \(value.diagnosticTypeName)")
        }
        let float = Float(bitPattern: 0x3f800001)
        try expect(try evaluate("f < d", ["f": .number(.float(float)), "d": .number(.double(Double(float)))]), "binary32 and binary64 retain distinct exact decimals")
        for form in LanguageFormValue.allCases {
            try expect(try evaluate("value == \(form.rawValue)", ["value": .languageForm(form)]), "typed form identity \(form.rawValue)")
            try expect(try !evaluate("value != \(form.rawValue)", ["value": .languageForm(form)]), "typed form inequality \(form.rawValue)")
        }
        let ordering: [(LanguageFormValue, String)] = [(.gender(.feminine), "gender"), (.grammaticalCase(.dative), "grammatical case"),
            (.definiteness(.definite), "definiteness"), (.classifier(.person), "classifier"), (.formality(.formal), "formality"),
            (.clusivity(.inclusive), "clusivity"), (.animacy(.animate), "animacy"), (.cardinality(.one), "cardinality"),
            (.ordinality(.one), "ordinality"), (.phonetic(.vowel), "phonetic")]
        for (form, noun) in ordering {
            _ = try refuse("a > b", ["a": .languageForm(form), "b": .languageForm(form)],
                           message: "You may only use the '==' and '!=' operators when performing \(noun) comparisons. Offending comparison: 'a > b'")
        }
        _ = try refuse("a == b", ["a": .languageForm(.gender(.feminine)), "b": .languageForm(.grammaticalCase(.dative))],
                       message: "Unable to evaluate expression 'a == b'. Operand runtime types Gender and GrammaticalCase are incompatible")
        _ = try refuse("a == GENDER_FEMININE", ["a": .languageForm(.cardinality(.one))], message: "Unable to extract Cardinality value from 'GENDER_FEMININE'")
        _ = try refuse("a == GENDER_FEMININE", ["a": .languageForm(.ordinality(.one))], message: "Unable to extract Ordinality value from 'GENDER_FEMININE'")

        try expect(try evaluate("1 == CARDINALITY_ONE && 1.0 == CARDINALITY_OTHER"), "literal decimal scale changes English cardinality")
        try expect(try evaluate("n == CARDINALITY_FEW", ["n": .integer(2)], locale: LocaleTag("ru")), "supplied catalog locale drives cardinality")
        try expect(try evaluate("n == CARDINALITY_OTHER", ["n": .number(.decimal(ExactDecimal("2.0")))], locale: LocaleTag("ru")), "visible decimal scale is retained")
        try expect(try evaluate("n == ORDINALITY_ONE", ["n": .integer(21)]), "numeric ordinal classification")
        try expect(try evaluate("n == ORDINALITY_OTHER", ["n": .integer(11)]), "ordinal teen exception")
        try expect(try evaluate("n == CARDINALITY_ONE && n < 0", ["n": .integer(-1)]), "absolute plural value and signed ordinary comparison")
        let compact = try PluralOperands.forNumber(ExactDecimal("-1.0"), compactExponent: 6)
        try expect(try evaluate("p == -1 && p != -1000000 && p == CARDINALITY_MANY", ["p": .pluralOperands(compact)], locale: LocaleTag("fr")), "compact source and expanded category remain separate")
        let explicit = try PluralOperands.forNumber(1, visibleDecimalPlaces: 1)
        try expect(try evaluate("p == 1 && p == CARDINALITY_OTHER", ["p": .pluralOperands(explicit)]), "explicit visible places affect classification but not source comparison")
        do { _ = try evaluate("1 == CARDINALITY_ONE", locale: LocaleTag("zz")); throw ConformanceError("Expected expression refusal") }
        catch let error as UnsupportedLocaleError { try expect(error.locale == "zz", "unsupported locale category remains untouched") }

        let lower = try TranslationRuntimeLimits(maximumNumberPrecision: 1, maximumVisibleDecimalPlaces: 0, maximumCompactExponent: 0)
        let malformed = try PluralOperands.forNumber(ExactDecimal("12.00"), visibleDecimalPlaces: 2, compactExponent: 1)
        let sourceFailure = try refuse("p == 1", ["p": .pluralOperands(malformed)], message: "Unable to extract numeric value from 'p': Plural operands value 'p' precision 4 exceeds the maximum of 1", limits: lower)
        try expect((sourceFailure.cause as? NumericError)?.kind == .invalidArgument, "numeric argument cause retained")
        _ = try refuse("p == 1", ["p": .pluralOperands(PluralOperands.forNumber(1, visibleDecimalPlaces: 2, compactExponent: 1))],
                       message: "Unable to extract numeric value from 'p': Plural operands compact exponent 1 exceeds the maximum of 0", limits: lower)
        _ = try refuse("p == 1", ["p": .pluralOperands(explicit)],
                       message: "Unable to extract numeric value from 'p': Plural operands visible decimal places 1 exceeds the maximum of 0", limits: lower)
        _ = try refuse("n == 1", ["n": .number(.decimal(ExactDecimal("1.00")))],
                       message: "Unable to extract numeric value from 'n': Numeric value 'n' precision 3 exceeds the maximum of 1", limits: lower)
        _ = try refuse("n == CARDINALITY_ONE", ["n": .number(.decimal(ExactDecimal("1.00")))],
                       message: "Unable to extract numeric value from 'n': Number precision 3 exceeds the maximum of 1", limits: lower)
        _ = try refuse("n == 1", ["n": .number(.bigInteger(String(repeating: "9", count: 5_000)))],
                       message: "Unable to extract numeric value from 'n': Numeric value 'n' precision 5000 exceeds the maximum of 1", limits: lower)

        let text: [ExactString: PlaceholderValue] = ["a": .text("book"), "b": .text("book"), "n": .integer(1)]
        _ = try refuse("a == b", text, message: "Raw CharSequence placeholders 'a' and 'b' cannot be compared with '==': expressions do not support textual equality. Compare phonetic input with a PHONETIC_* constant or an explicit Phonetic value instead")
        _ = try refuse("a < b", text, message: "Raw CharSequence placeholders 'a' and 'b' cannot be compared with '<': expressions do not support textual ordering. Use numeric operands for ordering, or compare phonetic input with a PHONETIC_* constant or an explicit Phonetic value using '==' or '!='")
        _ = try refuse("n == a", text, message: "Numeric comparison 'n == a' requires numeric operands supplied as Number or PluralOperands values, but placeholder 'a' resolved to String")
        _ = try refuse("a > n", text, message: "Numeric comparison 'a > n' requires numeric operands supplied as Number or PluralOperands values, but placeholder 'a' resolved to String")
        let log = ExpressionCallLog()
        let resolver: PhoneticResolver = { term, locale in log.append(term, locale); return .vowel }
        try expect(try evaluate("a == PHONETIC_VOWEL && a == PHONETIC_VOWEL", ["a": .text("é")], locale: LocaleTag("mo-MD"), resolver: resolver), "phonetic callback result")
        try expect(log.calls.map(\.0) == ["é", "é"] && log.calls.map { $0.1.tag } == ["mo-MD", "mo-MD"], "each site receives raw input and supplying locale")
        try expect(try evaluate("p == PHONETIC_VOWEL", ["p": .languageForm(.phonetic(.vowel))], resolver: resolver), "typed phonetic form requires no callback")
        try expect(log.calls.count == 2, "typed phonetic comparison bypasses callback")
        try expect(try evaluate("1 == 1 || a == PHONETIC_VOWEL", ["a": .text("apple")], resolver: resolver), "phonetic branch can be skipped")
        try expect(log.calls.count == 2, "skipped phonetic callback never runs")
        let original = ExpressionIdentityFailure()
        do { _ = try evaluate("a == PHONETIC_VOWEL", ["a": .text("apple")], resolver: { _, _ in throw original }); throw ConformanceError("Expected expression refusal") }
        catch { try expect((error as? ExpressionIdentityFailure) === original, "callback-thrown class identity retained") }
        let typedOriginal = TranslationEvaluationError(kind: .invalidState, message: "application typed failure")
        do { _ = try evaluate("a == PHONETIC_VOWEL", ["a": .text("apple")], resolver: { _, _ in throw typedOriginal }); throw ConformanceError("Expected expression refusal") }
        catch { try expect((error as? TranslationEvaluationError) === typedOriginal, "recognized resolver failure retained until contextual boundary") }
        _ = try refuse("a == PHONETIC_VOWEL", ["a": .text("a")], kind: .invalidState,
                       message: "No PhoneticResolver was configured. Provide one via Strings.Builder#phoneticResolver(...)")
        let inputLimits = try TranslationRuntimeLimits(maximumInterpolatedOutputCharacters: 1)
        let lengthFailure = try refuse("a == PHONETIC_VOWEL", ["a": .text("😀")],
                                      message: "Phonetic input for placeholder 'a' exceeds the maximum of 1 characters", limits: inputLimits)
        try expect((lengthFailure.cause as? TranslationEvaluationError)?.kind == .invalidArgument, "UTF16 input bound retains argument cause before default resolver")
        try expect(try evaluate("é == 1 && e\u{301} == 2", [ExactString("é"): .integer(1), ExactString("e\u{301}"): .integer(2)]), "NFC/NFD variable identities remain distinct")
        _ = try refuse("x == 1", ["x": .custom(ExpressionUnrenderedValue())], message: "Unable to evaluate expression 'x == 1'. Operand types UNKNOWN and NUMBER are unsupported")

        let lengthLimits = try TranslationRuntimeLimits(maximumExpressionCharacters: 3)
        do { _ = try ExpressionEvaluator.compile("1 == 1", runtimeLimits: lengthLimits); throw ConformanceError("Expected expression refusal") }
        catch let error as TranslationEvaluationError { try expect(error.kind == .expression && error.cause == nil, "length error is an expression leaf") }
        do { _ = try ExpressionEvaluator.compile("1 < 2 < 3"); throw ConformanceError("Expected expression refusal") }
        catch let error as TranslationEvaluationError {
            try expect(error.message.hasPrefix("Invalid expression '1 < 2 < 3': Chained comparisons"), "static type validation is eager")
            try expect((error.cause as? TranslationEvaluationError)?.kind == .expression && (error.cause as? TranslationEvaluationError)?.cause == nil, "static type error retains inner expression leaf")
        }
        do { _ = try ExpressionEvaluator.compile("1 == 1 || x == 1e1025"); throw ConformanceError("Expected expression refusal") }
        catch let error as TranslationEvaluationError { try expect((error.cause as? NumericError)?.kind == .invalidArgument, "unreachable invalid numeric literal fails eager compilation") }
        do { _ = try ExpressionEvaluator.compile("x == 1e1025\u{A0}"); throw ConformanceError("Expected expression refusal") }
        catch let error as TranslationEvaluationError { try expect(error.message.hasPrefix("Unexpected code point U+00A0") && error.cause == nil, "full lexing precedes numeric validation") }
        let ceilings = try TranslationRuntimeLimits(maximumExpressionCharacters: 4_096, maximumExpressionTokens: 512, maximumExpressionNestingDepth: 0)
        let deepestFlat = Array(repeating: "0 == 0", count: 128).joined(separator: " && ")
        try expect(try evaluate(deepestFlat, limits: ceilings), "flat 511-token expression evaluates iteratively")
        do { _ = try ExpressionEvaluator.compile(deepestFlat + " && 0 == 0", runtimeLimits: ceilings); throw ConformanceError("Expected expression refusal") }
        catch let error as TranslationEvaluationError { try expect(error.message.contains("exceeds maximum supported token count 512") && error.cause == nil, "hard token ceiling enforced eagerly") }
        return checks
    }
}

private final class ExpressionIdentityFailure: Error {}
private struct ExpressionUnrenderedValue: PlaceholderConvertible {
    func lokalizedDescription(maximumCharacters: Int?) throws -> String { throw ExpressionIdentityFailure() }
}
private final class ExpressionCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(String, LocaleTag)] = []
    var calls: [(String, LocaleTag)] { lock.lock(); defer { lock.unlock() }; return values }
    func append(_ term: String, _ locale: LocaleTag) { lock.lock(); defer { lock.unlock() }; values.append((term, locale)) }
}
