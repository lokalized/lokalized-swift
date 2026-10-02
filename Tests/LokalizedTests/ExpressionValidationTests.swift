import Foundation
import XCTest
@testable import Lokalized

final class ExpressionValidationTests: XCTestCase {
    func testPinnedIdentifierCategoriesAndUnicodeBoundaries() {
        for value in ["name", "_", "a-b", "é", "e\u{301}", "\u{11f04}", "\u{31350}", "a\u{2160}", "a\u{b2}"] {
            XCTAssertTrue(IdentifierRules.isIdentifier(value), value)
        }
        for value in ["", "-a", "1name", "\u{301}a", "\u{2160}", "\u{b2}", "a\u{200d}", "\u{1c89}", "\u{2ebf0}"] {
            XCTAssertFalse(IdentifierRules.isIdentifier(value), value)
        }
        XCTAssertEqual(IdentifierTables.unicodeVersion, "15.0")
        XCTAssertEqual(IdentifierTables.rangesSHA256, "d1c5f7947c2b761f6f9a7ca5b7ac3d9a0de473b3103698974053461a624a253c")
    }

    func testAll61ConstantsAndGreedyIdentifierRecovery() throws {
        var symbols: [String] = []
        func add<Form: LanguageForm & CaseIterable>(_ type: Form.Type) { symbols += Form.allCases.map(\.rawValue) }
        add(Cardinality.self); add(Ordinality.self); add(Gender.self); add(GrammaticalCase.self)
        add(Definiteness.self); add(Classifier.self); add(Formality.self); add(Clusivity.self)
        add(Animacy.self); add(Phonetic.self)
        XCTAssertEqual(symbols.count, 61)
        for symbol in symbols {
            let compiled = try ExpressionCompiler.compile("value == \(symbol)")
            guard case .operand(let type) = compiled.postfix[1].kind else { return XCTFail(symbol) }
            XCTAssertNotEqual(type, .unknownVariable, symbol)
            let suffixed = try ExpressionCompiler.compile("\(symbol)-X == 0")
            guard case .operand(let suffixType) = suffixed.postfix[0].kind else { return XCTFail(symbol) }
            XCTAssertEqual(suffixType, .unknownVariable)
        }
        try ExpressionCompiler.validate("true == false") // Identifiers, not literal boolean values.
        XCTAssertThrowsError(try ExpressionCompiler.validate("true"))
    }

    func testEveryPackedRangeBoundaryAndGap() throws {
        let data = try referenceJSON("identifier-data.json")
        let encoded = Array(try XCTUnwrap(data["ranges"] as? String).utf8)
        XCTAssertEqual(encoded.count, 1088 * 13)
        var prior: UInt32 = 0
        var letters = 0
        var continuations = 0
        for offset in stride(from: 0, to: encoded.count, by: 13) {
            let first = try XCTUnwrap(UInt32(String(decoding: encoded[offset..<(offset + 6)], as: UTF8.self), radix: 16))
            let last = try XCTUnwrap(UInt32(String(decoding: encoded[(offset + 6)..<(offset + 12)], as: UTF8.self), radix: 16))
            let isLetter = encoded[offset + 12] == 51
            for scalar in [first, last] {
                XCTAssertTrue(IdentifierTables.contains(scalar, start: false))
                XCTAssertEqual(IdentifierTables.contains(scalar, start: true), isLetter)
            }
            if first > prior + 1 { XCTAssertFalse(IdentifierTables.contains(first - 1, start: false)) }
            continuations += Int(last - first + 1)
            if isLetter { letters += Int(last - first + 1) }
            prior = last
        }
        XCTAssertEqual(letters, 136_104)
        XCTAssertEqual(continuations, 140_385)
        for scalar in [UInt32(0), 0xd800, 0xdfff, 0x10ffff, 0x110000] {
            XCTAssertFalse(IdentifierTables.contains(scalar, start: false))
        }
    }

    func testRealPostfixPrecedenceAndExactNumericMetadata() throws {
        let compiled = try ExpressionCompiler.compile("n == 1 || n == 2 && n == 3")
        XCTAssertEqual(compiled.postfix.map(\.symbol), ["n", "1", "==", "n", "2", "==", "n", "3", "==", "&&", "||"])
        let decimal = try ExpressionCompiler.compile("n == -0001.2300e+2").postfix[1].numeric
        XCTAssertEqual(decimal?.coefficient, "12300")
        XCTAssertEqual(decimal?.scale, 2)
        XCTAssertEqual(decimal?.negative, true)
        let zero = try ExpressionCompiler.compile("n == 0.0000").postfix[1].numeric
        XCTAssertEqual(zero?.coefficient, "0")
        XCTAssertEqual(zero?.scale, 4)
        for source in ["n == 01.", "n == +.4", "n == 1e000000000000000000001", "1() == 1"] {
            XCTAssertNoThrow(try ExpressionCompiler.validate(source))
        }
    }

    func testValidationOrderLimitsAndJavaNumericDiagnostics() throws {
        let long = String(repeating: " ", count: 2050) + "n == 1"
        XCTAssertNoThrow(try ExpressionCompiler.validate(long))
        XCTAssertThrowsError(try ExpressionCompiler.validate(long, limits: .defaults)) {
            XCTAssertEqual(($0 as? ExpressionCompilationError)?.reason, .characterLimit)
        }
        let cases: [(String, String)] = [
            ("n == 1e12345678901", "Invalid numeric literal '1e12345678901': Too many nonzero exponent digits."),
            ("n == 1e-2147483648", "Invalid numeric literal '1e-2147483648': Exponent overflow."),
            ("n == 1e2147483648", "Invalid numeric literal '1e2147483648': Numeric literal '1e2147483648' scale -2147483648 exceeds the maximum absolute scale of 4096"),
            ("n == 1e10000", "Invalid numeric literal '1e10000': Numeric literal '1e10000' scale -10000 exceeds the maximum absolute scale of 4096"),
            ("n == 1e+", "Unexpected code point U+002B at index 7 while evaluating expression 'n == 1e+'.")
        ]
        for (source, expected) in cases {
            XCTAssertThrowsError(try ExpressionCompiler.validate(source)) {
                XCTAssertEqual(($0 as? ExpressionCompilationError)?.message, expected)
            }
        }
        XCTAssertThrowsError(try ExpressionCompiler.validate("1e10000 == 0 ?")) {
            XCTAssertEqual(($0 as? ExpressionCompilationError)?.reason, .lexical)
        }
        let limits = try TranslationRuntimeLimits(maximumNumberPrecision: 2, maximumAbsoluteNumberScale: 2, maximumExpressionTokens: 3)
        XCTAssertThrowsError(try ExpressionCompiler.validate("123.000 == 0 && n == 2", limits: limits)) {
            XCTAssertEqual(($0 as? ExpressionCompilationError)?.message, "Invalid numeric literal '123.000': Numeric literal '123.000' scale 3 exceeds the maximum absolute scale of 2")
        }
        XCTAssertThrowsError(try ExpressionCompiler.validate("123 == 0", limits: limits)) {
            XCTAssertEqual(($0 as? ExpressionCompilationError)?.message, "Invalid numeric literal '123': Numeric literal '123' precision 3 exceeds the maximum of 2")
        }
        XCTAssertThrowsError(try ExpressionCompiler.validate("\u{10400} ? 0")) {
            XCTAssertEqual(($0 as? ExpressionCompilationError)?.message, "Unexpected code point U+003F at index 3 while evaluating expression '\u{10400} ? 0'.")
        }
    }

    func testEveryRecordedParseExpressionDiagnostic() throws {
        let corpus = try referenceJSON("behavioral-vectors.json")
        let fixtures = try XCTUnwrap(corpus["fixtures"] as? [String: Any])
        let rows = try XCTUnwrap(corpus["cases"] as? [[String: Any]])
        var checked = 0
        for row in rows where row["operation"] as? String == "parse" {
            let expected = try XCTUnwrap(row["expected"] as? [String: Any])
            let parse = try XCTUnwrap(expected["parse"] as? [String: Any])
            guard let message = parse["failureMessage"] as? String,
                  message.contains("unable to parse "), message.contains(" expression ") else { continue }
            let input = try XCTUnwrap(row["input"] as? [String: Any])
            let fixture = try XCTUnwrap(fixtures[try XCTUnwrap(row["fixture"] as? String)] as? [String: Any])
            let files = try XCTUnwrap(fixture["files"] as? [String: Any])
            let catalog = try XCTUnwrap(files[try XCTUnwrap(input["file"] as? String)])
            let expressions = collectExpressions(catalog)
            var actual: ExpressionCompilationError?
            for expression in expressions {
                do { try ExpressionCompiler.validate(expression) }
                catch let error as ExpressionCompilationError { actual = error; break }
            }
            let error = try XCTUnwrap(actual, "No compilation failure for \(row["id"] ?? "?")")
            XCTAssertTrue(message.hasSuffix(": " + error.message), "\(row["id"] ?? "?"): \(error.message)")
            checked += 1
        }
        XCTAssertEqual(checked, 31, "Frozen expression diagnostic inventory changed")
    }

    private func collectExpressions(_ value: Any) -> [String] {
        if let array = value as? [Any] { return array.flatMap(collectExpressions) }
        guard let object = value as? [String: Any] else { return [] }
        var result: [String] = []
        for key in object.keys.sorted() {
            let nested = object[key]!
            if key == "alternatives", let alternatives = nested as? [[String: Any]] {
                for alternative in alternatives {
                    for expression in alternative.keys.sorted() {
                        result.append(expression)
                        result += collectExpressions(alternative[expression]!)
                    }
                }
            } else { result += collectExpressions(nested) }
        }
        return result
    }

    private func referenceJSON(_ name: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Reference").appendingPathComponent(name))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
