import Foundation
import XCTest
@testable import Lokalized

final class CatalogParserTests: XCTestCase {
    func testExactUnicodeKeysAndHostileObjectNames() throws {
        let file = try LocalizedStringLoader.parse(#"{"é":"a","e\u0301":"b","__proto__":"c","constructor":"d"}"#, locale: "en", source: "keys")
        XCTAssertEqual(file.strings.count, 4)
        XCTAssertEqual(Set(file.strings.map(\.key)).count, 4)
        XCTAssertEqual(file.originsByKey[ExactString("e\u{0301}")], ["keys"])
    }

    func testByteAndReaderBoundariesRemainDistinctAndCountBOM() throws {
        let options = try LocalizedStringLoadingOptions(maximumReaderCharacters: 1)
        XCTAssertEqual(try LocalizedStringLoader.parse(Data("{}".utf8), locale: "en", loadingOptions: options).strings.count, 0)
        XCTAssertEqual(try refusal("{}", options: options).message, "test: localized strings resource exceeds the maximum size of 1 characters")
        let bom = try LocalizedStringLoadingOptions(maximumReaderCharacters: 2)
        XCTAssertEqual(try refusal("\u{FEFF}{}", options: bom).message, "test: localized strings resource exceeds the maximum size of 2 characters")
    }

    func testStrictUTF8AndExactlyOneBOM() throws {
        XCTAssertThrowsError(try LocalizedStringLoader.parse(Data([0xC0, 0x80]), locale: "en", source: "bytes")) { error in
            XCTAssertEqual((error as? StringsParseError)?.message, "bytes: localized strings resource is not valid UTF-8")
        }
        XCTAssertTrue(try LocalizedStringLoader.parse("\u{FEFF}{}", locale: "en").strings.isEmpty)
        XCTAssertEqual(try refusal("\u{FEFF}\u{FEFF}{}").message, "test:1:1: unable to parse localized strings file")
        XCTAssertThrowsError(try LocalizedStringLoader.parse(Data("\u{FEFF}\u{FEFF}{}".utf8), locale: "en", source: "bom")) { error in
            XCTAssertEqual((error as? StringsParseError)?.message, "bom:1:1: unable to parse localized strings file")
        }
        XCTAssertEqual(try refusal("\u{FEFF}\t\r\n").message, "test: a localized strings file may not be blank; use an empty JSON object ({}) for an empty file")
    }

    func testAggregateByteFailurePrecedesPerFileFailure() throws {
        let options = try LocalizedStringLoadingOptions(maximumInputBytes: 4, maximumTotalInputBytes: 3)
        XCTAssertThrowsError(try LocalizedStringLoader.parse(Data("abcde".utf8), locale: "en", source: "bytes", loadingOptions: options)) { error in
            XCTAssertEqual((error as? StringsParseError)?.message, "bytes: localized strings load exceeds the aggregate maximum of 3 input bytes")
        }
    }

    func testUnsupportedEscapeReportsCurrentUTF16UnitForBothInputDoors() throws {
        // Minimized from the differential probe; the offending x remains current.
        let cases: [(String, Int, Int)] = [
            (#""\x"#, 1, 3),
            (#"{"a":"\x"}"#, 1, 8),
            ("\u{FEFF}{\"a\":\"\\x\"}", 1, 8),
            ("\r\n{\"😀\":\"\\q\"}", 2, 9),
            ("{\"a\":\"\\\n\"}", 1, 8)
        ]
        for (text, line, column) in cases {
            for parse in [
                { try LocalizedStringLoader.parse(text, locale: "en", source: "escape") },
                { try LocalizedStringLoader.parse(Data(text.utf8), locale: "en", source: "escape") }
            ] {
                XCTAssertThrowsError(try parse()) {
                    let error = $0 as? StringsParseError
                    XCTAssertEqual(error?.message, "escape:\(line):\(column): unable to parse localized strings file")
                    XCTAssertEqual(error?.line, line); XCTAssertEqual(error?.column, column)
                    XCTAssertEqual((error?.cause as? JSONReadError)?.reason, "Invalid string escape")
                }
            }
        }
    }

    func testSurrogateValidationPreservesCompetingSyntaxErrorPriority() throws {
        let cases: [(String, Int)] = [
            (#""\uD800"#, 8),
            (#"{"a":"\uD800"#, 13),
            (#"{"a":"\uD800\x"}"#, 14),
            ("{\"a\":\"\\uD800\n\"}", 13),
            (#"{"a":"\uD800x"}"#, 7),
            (#"{"a":"\uD800\u0000"}"#, 7),
            (#"{"a":"\uDC00"}"#, 7)
        ]
        for (text, column) in cases {
            for parse in [
                { _ = try LocalizedStringLoader.parse(text, locale: "en", source: "surrogate") },
                { _ = try LocalizedStringLoader.parse(Data(text.utf8), locale: "en", source: "surrogate") },
                { _ = try LocalizedStringLoader.parseStringsManifest(text, source: "surrogate") },
                { _ = try LocalizedStringLoader.parseStringsManifest(Data(text.utf8), source: "surrogate") }
            ] {
                XCTAssertThrowsError(try parse()) {
                    XCTAssertEqual(($0 as? StringsParseError)?.message,
                                   "surrogate:1:\(column): unable to parse localized strings file")
                }
            }
        }
        let paired = try LocalizedStringLoader.parse(#"{"a":"\uD83D\uDE00😀"}"#, locale: "en")
        XCTAssertEqual(paired.strings.first?.translation?.utf16.map(Int.init), [0xD83D, 0xDE00, 0xD83D, 0xDE00])
    }

    func testDuplicatePrescanPrecedesSchemaWithinRootAndLaterRootsRemainLater() throws {
        let same = try refusal(#"{"A":{"oops":1,"translation":"x","translation":"y"}}"#)
        XCTAssertEqual(same.message, "test: duplicate JSON object member 'translation' encountered at $.A")
        XCTAssertEqual(same.path, "$.A")
        let earlier = try refusal(#"{"A":3,"B":{"translation":"x","translation":"y"}}"#)
        XCTAssertEqual(earlier.message, "test: either a translation string or object value is required for key 'A'")
        XCTAssertEqual(try refusal(#"{"A":"x","\u0041":"y"}"#).message, "test: duplicate localized string key 'A' encountered")
    }

    func testWarningsArriveBeforeLaterErrorsAndRefusedWarningIsNotDelivered() throws {
        let input = #"{"A":{"translation":"{{n}}","placeholders":{"n":{"value":"count","translations":{"CARDINALITY_ONE":"one"}}}},"B":null}"#
        let recorder = WarningRecorder()
        XCTAssertThrowsError(try LocalizedStringLoader.parse(input, locale: "ru", source: "warnings", warningHandler: { recorder.append($0) }))
        XCTAssertEqual(recorder.values.count, 1)
        XCTAssertEqual(recorder.values.first?.missingLanguageForms, ["CARDINALITY_FEW", "CARDINALITY_MANY", "CARDINALITY_OTHER"])
        let refused = WarningRecorder()
        let options = try LocalizedStringLoadingOptions(maximumWarnings: 0)
        XCTAssertThrowsError(try LocalizedStringLoader.parse(input, locale: "ru", source: "warnings", warningHandler: { refused.append($0) }, loadingOptions: options)) { error in
            XCTAssertEqual((error as? StringsParseError)?.message, "warnings: localized strings load exceeds the aggregate maximum of 0 warnings")
        }
        XCTAssertTrue(refused.values.isEmpty)
    }

    func testRootNodeBudgetChargedBeforeStructuralWalk() throws {
        let options = try LocalizedStringLoadingOptions(maximumTranslationNodes: 1)
        XCTAssertEqual(try refusal(#"{"A":null,"B":"x"}"#, options: options).message, "test: localized strings load exceeds the aggregate maximum of 1 translation nodes")
        XCTAssertTrue(try LocalizedStringLoader.parse("{}", locale: "en", loadingOptions: try .init(maximumTranslationNodes: 0)).strings.isEmpty)
    }

    func testNestedExpressionsCompileEagerlyAgainstCeilings() throws {
        let accepted = String(repeating: " ", count: 2_049) + "count == 1"
        let input = "{\"A\":{\"alternatives\":[{\"\(accepted)\":\"one\"}]}}"
        XCTAssertEqual(try LocalizedStringLoader.parse(input, locale: "en").strings.count, 1)
        let invalid = try refusal(#"{"A":{"alternatives":[{"count ==":"x"}]},"B":null}"#)
        XCTAssertTrue(invalid.message.hasPrefix("test: unable to parse whole-message alternative expression 'count ==' for root key 'A': "))
    }

    func testDelimiterScanningUsesCodeUnitsAndExactEscapes() throws {
        XCTAssertEqual(try refusal(#"{"A":"😀}}́"}"#).message, "test: invalid placeholder reference in translation for key 'A': Unexpected placeholder closing delimiter '}}' at index 2")
        XCTAssertNoThrow(try LocalizedStringLoader.parse(#"{"A":"\\{{not a name}} \\}} \\\\ {{é}}"}"#, locale: "en"))
        XCTAssertTrue(try refusal(#"{"A":"{{CARDINALITY_ONE}}"}"#).message.contains("reserved expression constants"))
    }

    func testCompleteModelsAndSourceAwareRangeRefusal() throws {
        let input = #"{"A":{"translation":"{{fragment}}","commentary":"note","placeholders":{"fragment":{"translation":"default","alternatives":[{"count == 1":"one"}]},"range":{"range":{"start":"lo","end":"hi"},"translations":{"CARDINALITY_OTHER":"many"}}}}}"#
        let file = try LocalizedStringLoader.parse(input, locale: "en", source: "models")
        XCTAssertEqual(file.strings.first?.commentary, "note")
        XCTAssertEqual(file.strings.first?.placeholderDefinitions.count, 2)
        XCTAssertTrue(file.warnings.isEmpty)
        XCTAssertTrue(try refusal(#"{"A":{"translation":"x","placeholders":{"p":{"range":{"start":"lo","end":"hi"},"translations":{"GENDER_MASCULINE":"m"}}}}}"#).message.contains("range-based translations only support Cardinality"))
    }

    func testShardDedupConflictAndPostDedupBudget() throws {
        let a = try LocalizedStringLoader.parse(#"{"A":{"translation":"a","commentary":"note"}}"#, locale: "en-us", source: "a")
        let b = try LocalizedStringLoader.parse(#"{"A":{"commentary":"note","translation":"a"}}"#, locale: "en-US", source: "b")
        let merged = try LocalizedStringLoader.mergeParsedStringsFiles([a, b], loadingOptions: try .init(maximumTranslationNodes: 1))
        XCTAssertEqual(merged.locale, "en-US")
        XCTAssertEqual(merged.strings.count, 1)
        XCTAssertEqual(merged.originsByKey["A"], ["a", "b"])
        let conflict = try LocalizedStringLoader.parse(#"{"A":{"translation":"a","commentary":"other"}}"#, locale: "en-US", source: "c")
        XCTAssertThrowsError(try LocalizedStringLoader.mergeParsedStringsFiles([a, conflict])) { error in
            XCTAssertTrue((error as? StringsParseError)?.message.contains("defined differently in [a] and [c]") == true)
        }
        let different = try LocalizedStringLoader.parse("{}", locale: "pt-PT")
        XCTAssertThrowsError(try LocalizedStringLoader.mergeParsedStringsFiles([a, different]))
    }

    func testTypedDefinitionValidationHasNoRawJSONDepthOrByteCharge() throws {
        let form = LanguageFormTranslation(value: "count", translationsByLanguageForm: [.cardinality(.one): "one"])
        let model = try LocalizedString(key: "A", translation: "{{n}}", placeholderDefinitions: ["n": .languageForm(form)])
        let options = try LocalizedStringLoadingOptions(maximumInputBytes: 1, maximumReaderCharacters: 1, maximumJsonNestingDepth: 1, maximumTotalInputBytes: 1)
        let defined = try LocalizedStringLoader.defineCatalog([model], locale: "ru", loadingOptions: options)
        XCTAssertEqual(defined.strings.count, 1)
        XCTAssertEqual(defined.warnings.count, 1)
        let invalid = try LocalizedString(key: "B", translation: "{{1bad}}")
        XCTAssertThrowsError(try LocalizedStringLoader.defineCatalog([invalid], locale: "en"))
    }

    func testWarningLocaleExtlangAndUnsupportedProjection() throws {
        let input = #"{"A":{"translation":"{{n}}","placeholders":{"n":{"value":"count","translations":{"CARDINALITY_ONE":"one"}}}}}"#
        XCTAssertEqual(try LocalizedStringLoader.parse(input, locale: "ru-SU").warnings.first?.locale, "ru-SU")
        let extlang = try LocalizedStringLoader.parse(input, locale: "ru-SUN")
        XCTAssertEqual(extlang.locale, "sun")
        XCTAssertEqual(extlang.warnings.count, 1)
        XCTAssertTrue(try LocalizedStringLoader.parse(input, locale: "zz").warnings.isEmpty)
    }

    func testSharedModelSubtreeIsBoundedBeforeProjectionCanExpand() throws {
        var node = try LocalizedString(key: "n == 1", translation: "leaf")
        for _ in 0..<120 { node = try LocalizedString(key: "n == 1", alternatives: [node, node]) }
        let root = try LocalizedString(key: "A", alternatives: [node])
        XCTAssertNoThrow(try LocalizedStringLoader.defineCatalog([root], locale: "en"))
        XCTAssertThrowsError(try LocalizedStringLoader.defineCatalog([root], locale: "en", source: "shared", loadingOptions: try .init(maximumTranslationNodes: 32))) { error in
            XCTAssertEqual((error as? StringsParseError)?.message, "shared: localized strings load exceeds the aggregate maximum of 32 translation nodes")
        }
    }

    func testSharedNodeWarningsOncePerRootAndDepthRevalidatedAtDeeperPlacement() throws {
        let form = LanguageFormTranslation(value: "count", translationsByLanguageForm: [.cardinality(.one): "one"])
        let leaf = try LocalizedString(key: "n == 1", translation: "{{n}}", placeholderDefinitions: ["n": .languageForm(form)])
        let a = try LocalizedString(key: "A", alternatives: [leaf, leaf])
        let b = try LocalizedString(key: "B", alternatives: [leaf])
        let catalog = try LocalizedStringLoader.defineCatalog([a, b], locale: "ru")
        XCTAssertEqual(catalog.warnings.map(\.key), [ExactString("A"), ExactString("B")])
        var subtree = leaf
        for _ in 0..<127 { subtree = try LocalizedString(key: "n == 1", alternatives: [subtree]) }
        let bridge = try LocalizedString(key: "n == 1", alternatives: [subtree])
        let deepRoot = try LocalizedString(key: "Depth", alternatives: [subtree, bridge])
        XCTAssertThrowsError(try LocalizedStringLoader.defineCatalog([deepRoot], locale: "en")) { error in
            XCTAssertEqual((error as? StringsParseError)?.message, "<defined>: alternative nesting exceeds the maximum depth of 128 for key 'Depth'")
        }
    }

    func testTypedAndFileValidationAgreeOnNestedPlaceholderKeyContext() throws {
        let form = LanguageFormTranslation(value: "n", translationsByLanguageForm: [.cardinality(.one): "one"])
        let branch = try LocalizedString(key: "n == 1", translation: "x", placeholderDefinitions: ["1bad": .languageForm(form)])
        let model = try LocalizedString(key: "A", alternatives: [branch])
        let file = #"{"A":{"alternatives":[{"n == 1":{"translation":"x","placeholders":{"1bad":{"value":"n","translations":{"CARDINALITY_ONE":"one"}}}}}]}}"#
        let fileFailure = try refusal(file)
        XCTAssertTrue(fileFailure.message.hasSuffix("Key is 'n == 1'"))
        XCTAssertThrowsError(try LocalizedStringLoader.defineCatalog([model], locale: "en", source: "test")) { error in
            XCTAssertEqual((error as? StringsParseError)?.message, fileFailure.message)
        }
        let ranged = LanguageFormTranslation(range: .init(start: "1lo", end: "hi"), translationsByLanguageForm: [.cardinality(.one): "one"])
        let rangeBranch = try LocalizedString(key: "n == 1", translation: "x", placeholderDefinitions: ["p": .languageForm(ranged)])
        let rangeRoot = try LocalizedString(key: "A", alternatives: [rangeBranch])
        let rangeFile = #"{"A":{"alternatives":[{"n == 1":{"translation":"x","placeholders":{"p":{"range":{"start":"1lo","end":"hi"},"translations":{"CARDINALITY_ONE":"one"}}}}}]}}"#
        let rangeFailure = try refusal(rangeFile)
        XCTAssertTrue(rangeFailure.message.hasSuffix("Key is 'A'"))
        XCTAssertThrowsError(try LocalizedStringLoader.defineCatalog([rangeRoot], locale: "en", source: "test")) { error in
            XCTAssertEqual((error as? StringsParseError)?.message, rangeFailure.message)
        }
    }

    func testTypedAndFileValidationKeepExpressionAndTranslationPriority() throws {
        let branch = try LocalizedString(key: "n ==", translation: "x")
        let model = try LocalizedString(key: "A", translation: "{{1bad}}", alternatives: [branch])
        let file = #"{"A":{"translation":"{{1bad}}","alternatives":[{"n ==":"x"}]}}"#
        let expected = try refusal(file)
        XCTAssertTrue(expected.message.contains("unable to parse whole-message alternative expression"))
        XCTAssertThrowsError(try LocalizedStringLoader.defineCatalog([model], locale: "en", source: "test")) { error in
            XCTAssertEqual((error as? StringsParseError)?.message, expected.message)
        }
    }

    private func refusal(_ input: String, options: LocalizedStringLoadingOptions = .defaults) throws -> StringsParseError {
        do { _ = try LocalizedStringLoader.parse(input, locale: "en", source: "test", loadingOptions: options) }
        catch let error as StringsParseError { return error }
        throw ExpectedRefusal.missing
    }
    private enum ExpectedRefusal: Error { case missing }
}

private final class WarningRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [LocalizedStringWarning] = []
    var values: [LocalizedStringWarning] { lock.lock(); defer { lock.unlock() }; return held }
    func append(_ warning: LocalizedStringWarning) { lock.lock(); defer { lock.unlock() }; held.append(warning) }
}
