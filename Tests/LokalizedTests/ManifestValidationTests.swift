import Foundation
import XCTest
@testable import Lokalized
@testable import LokalizedConformanceSupport

final class ManifestValidationTests: XCTestCase {
    private func manifest() throws -> StringsManifestV1 {
        let files: [ExactString: StringsManifestFile] = ["en": .init(url: "en.json", sha256: String(repeating: "a", count: 64))]
        let identity = try LocalizedStringLoader.computeCatalogIdentity(.init(catalogVersion: "v1", resolvedFallbackLocale: "en", localeToSha256: files.mapValues(\.sha256)))
        return .init(catalogVersion: "v1", catalogFingerprint: identity.catalogFingerprint, fallbackLocale: "en",
                     baseUrl: "https://cdn.example/v1/", files: files)
    }
    private func text() throws -> String {
        let manifest = try manifest()
        let value: [String: Any] = ["formatVersion": 1, "catalogVersion": manifest.catalogVersion,
            "catalogFingerprint": manifest.catalogFingerprint, "cldrVersion": manifest.cldrVersion,
            "dataFingerprint": manifest.dataFingerprint, "behavioralVectorsVersion": manifest.behavioralVectorsVersion,
            "localeDataMode": manifest.localeDataMode, "cardinalityMode": manifest.cardinalityMode,
            "ianaRegistryDate": manifest.ianaRegistryDate, "ianaDataFingerprint": manifest.ianaDataFingerprint,
            "fallbackLocale": manifest.fallbackLocale, "baseUrl": manifest.baseUrl,
            "files": ["en": ["url": "en.json", "sha256": String(repeating: "a", count: 64)]],
            "tiebreakerLocalesByLanguageCode": [:] as [String: Any]]
        return String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
    func testStandaloneManifestValidationQualification() throws {
        XCTAssertEqual(try ConformanceRunner.manifestValidationSelfTest(), 118)
    }
    func testTextAndByteDoorsAgreeAndPreserveRawURLSpelling() throws {
        let text = try text()
        let fromText = try LocalizedStringLoader.parseStringsManifest(text, source: "wire")
        let fromBytes = try LocalizedStringLoader.parseStringsManifest(Data(text.utf8), source: "wire")
        XCTAssertEqual(fromBytes.catalogFingerprint, fromText.catalogFingerprint)
        XCTAssertEqual(fromText.baseUrl, "https://cdn.example/v1/")
        XCTAssertEqual(fromText.files["en"]?.url, "en.json")
        XCTAssertEqual(try LocalizedStringLoader.validateStringsManifest(fromBytes).catalogFingerprint, fromText.catalogFingerprint)
    }
    func testUnfinishedURLCapabilityCauseSurvivesEveryValidationDoor() throws {
        let text = try text()
        let unicodeBase = text.replacingOccurrences(of: "https://cdn.example/v1/", with: "https://bücher.example/v1/")
        let unicodeEntry = text.replacingOccurrences(of: #""url":"en.json""#, with: #""url":"https://xn--bcher-kva.example/en.json""#)
        for input in [unicodeBase, unicodeEntry] {
            for parse in [
                { try LocalizedStringLoader.parseStringsManifest(input) },
                { try LocalizedStringLoader.parseStringsManifest(Data(input.utf8)) }
            ] {
                XCTAssertThrowsError(try parse()) {
                    guard let failure = ($0 as? ConfigurationError)?.cause as? ManifestURL.Failure,
                          case .unsupportedFeature = failure.kind else { return XCTFail("URL capability cause was lost: \($0)") }
                }
            }
        }
        guard case .object(var members) = try manifest().decodedValue else { return XCTFail("fixture shape") }
        members.removeAll { $0.name == "baseUrl" }
        members.append(.init(name: "baseUrl", value: .string("https://bücher.example/")))
        XCTAssertThrowsError(try LocalizedStringLoader.validateStringsManifest(.object(members))) {
            XCTAssertNotNil(($0 as? ConfigurationError)?.cause as? ManifestURL.Failure)
        }
        let malformed = text.replacingOccurrences(of: "https://cdn.example/v1/", with: "relative/base")
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(malformed)) {
            XCTAssertNil(($0 as? ConfigurationError)?.cause)
        }
    }
    func testRootDuplicateWinsBeforeEarlierNestedDuplicateAndSchemaError() throws {
        let text = try text()
        let duplicate = String(text.dropLast()) + #", "extra":{"nested":1,"nested":2}, "formatVersion":2}"#
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(duplicate, source: "wire")) {
            let error = $0 as? StringsParseError
            XCTAssertEqual(error?.message, "wire: duplicate manifest member 'formatVersion' encountered")
            XCTAssertNil(error?.line); XCTAssertNil(error?.column); XCTAssertNil(error?.path)
        }
        let nested = String(text.dropLast()) + #", "extra":{"nested":1,"nested":2}}"#
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(nested, source: "wire")) {
            let error = $0 as? StringsParseError
            XCTAssertEqual(error?.message, "wire: duplicate JSON object member 'nested' encountered at $.extra")
            XCTAssertNil(error?.path)
        }
        let syntax = duplicate + "!"
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(syntax, source: "wire")) {
            XCTAssertNotNil(($0 as? StringsParseError)?.line, "whole source syntax precedes duplicate walk")
        }
    }
    func testNestedDuplicateReportsFirstDocumentOccurrenceIncludingUnknownFieldsAndArrayRoot() throws {
        let prefix = #"{"extra":{"child":{"a":1,"a":2},"x":1,"x":2},"formatVersion":2}"#
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(prefix, source: "wire")) {
            XCTAssertEqual(($0 as? StringsParseError)?.message, "wire: duplicate JSON object member 'a' encountered at $.extra.child")
            XCTAssertNil(($0 as? StringsParseError)?.path)
        }
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(#"[{"x":1,"x":2}]"#, source: "wire")) {
            XCTAssertEqual(($0 as? StringsParseError)?.message, "wire: duplicate JSON object member 'x' encountered at $[0]")
            XCTAssertNil(($0 as? StringsParseError)?.path)
        }
        let exact = String(try text().dropLast()) + #", "extra":{"é":1,"e\u0301":2}}"#
        XCTAssertNoThrow(try LocalizedStringLoader.parseStringsManifest(exact))
        let equal = String(try text().dropLast()) + #", "extra":{"é":1,"\u00e9":2}}"#
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(equal)) { XCTAssertTrue($0 is StringsParseError) }
    }
    func testRawAndObjectCapabilitiesDifferWithoutInventingLocations() throws {
        let input = try manifest().decodedValue
        guard case .object(let members) = input else { return XCTFail("fixture shape") }
        let duplicated = StringsManifestValue.object([.init(name: "formatVersion", value: .number(2))] + members)
        XCTAssertEqual(try LocalizedStringLoader.validateStringsManifest(duplicated).formatVersion, 1)
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest("{\n \"x\":", source: "wire")) {
            let error = $0 as? StringsParseError
            XCTAssertEqual(error?.line, 2); XCTAssertEqual(error?.column, 6)
            XCTAssertNotNil(error?.cause)
        }
        XCTAssertThrowsError(try LocalizedStringLoader.validateStringsManifest(.object([]))) {
            XCTAssertEqual(($0 as? ConfigurationError)?.message, "A strings manifest must declare formatVersion 1; received undefined")
        }
    }
    func testManifestUnsupportedEscapeCursorPointsAtTheOffendingUTF16Unit() throws {
        let cases: [(String, Int, Int, Int, String)] = [
            (#"{"x":"\q"}"#, 1, 8, 7, "Invalid string escape"),
            ("{\r\n\"😀\":\"\\q\"}", 2, 8, 10, "Invalid string escape"),
            ("{\"x\":\"\\\n\"}", 1, 8, 7, "Invalid string escape"),
            (#"{"x":"\u00q0"}"#, 1, 11, 10, "Invalid Unicode escape"),
            ("{\r?}", 2, 1, 2, "Expected object member name"),
            ("{\r\n?}", 2, 1, 3, "Expected object member name"),
            ("{\n?}", 2, 1, 2, "Expected object member name")
        ]
        for (text, line, column, offset, reason) in cases {
            for parse in [
                { try LocalizedStringLoader.parseStringsManifest(text, source: "wire") },
                { try LocalizedStringLoader.parseStringsManifest(Data(text.utf8), source: "wire") }
            ] {
                XCTAssertThrowsError(try parse()) {
                    let error = $0 as? StringsParseError
                    let cause = error?.cause as? JSONReadError
                    XCTAssertEqual(error?.message, "wire:\(line):\(column): unable to parse localized strings file")
                    XCTAssertEqual(error?.line, line); XCTAssertEqual(error?.column, column)
                    XCTAssertEqual(cause?.reason, reason); XCTAssertEqual(cause?.location.offset, offset)
                    XCTAssertEqual(cause?.location.line, line); XCTAssertEqual(cause?.location.column, column)
                }
            }
        }
        XCTAssertThrowsError(try JSONReader.parse(#"{"x":"\q"}"#)) {
            XCTAssertEqual(($0 as? JSONReadError)?.location.column, 9, "shared catalog reader behavior is unchanged")
        }
    }
    func testManifestByteInputEnforcesBothByteAndUTF16CharacterCapsWithoutAggregateCharge() throws {
        let text = try text(), data = Data(text.utf8)
        XCTAssertNoThrow(try LocalizedStringLoader.parseStringsManifest(data, loadingOptions: .init(maximumTotalInputBytes: 1, maximumTranslationNodes: 0, maximumWarnings: 0)))
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(data, source: "wire", loadingOptions: .init(maximumInputBytes: data.count - 1))) {
            XCTAssertEqual(($0 as? StringsParseError)?.message, "wire: localized strings resource exceeds the maximum size of \(data.count - 1) bytes")
        }
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(data, source: "wire", loadingOptions: .init(maximumReaderCharacters: text.utf16.count - 1))) {
            XCTAssertEqual(($0 as? StringsParseError)?.message, "wire: localized strings resource exceeds the maximum size of \(text.utf16.count - 1) characters")
        }
        XCTAssertNoThrow(try LocalizedStringLoader.parseStringsManifest(text, loadingOptions: .init(maximumInputBytes: 1)))
    }
    func testExactlyOneBOMAndDepthBeforeSyntaxAndStrictUTF8() throws {
        let text = try text()
        XCTAssertNoThrow(try LocalizedStringLoader.parseStringsManifest("\u{FEFF}" + text))
        XCTAssertNoThrow(try LocalizedStringLoader.parseStringsManifest(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)))
        for input in ["\u{FEFF}\u{FEFF}" + text, "\u{00A0}"] {
            XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(input, source: "wire")) {
                XCTAssertEqual(($0 as? StringsParseError)?.line, 1); XCTAssertEqual(($0 as? StringsParseError)?.column, 1)
            }
        }
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest("\u{FEFF} \r\n", source: "wire")) {
            XCTAssertTrue(($0 as? StringsParseError)?.message.contains("may not be blank") == true)
        }
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest("{\"a\":{ broken", source: "wire", loadingOptions: .init(maximumJsonNestingDepth: 1))) {
            XCTAssertEqual(($0 as? StringsParseError)?.message, "wire: JSON nesting depth exceeds the maximum of 1")
            XCTAssertNil(($0 as? StringsParseError)?.line)
        }
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(Data([0xC0, 0xAF]), source: "wire")) {
            XCTAssertEqual(($0 as? StringsParseError)?.message, "wire: localized strings resource is not valid UTF-8")
            XCTAssertNotNil(($0 as? StringsParseError)?.cause)
        }
    }
    func testRawSchemaNumbersUseBinary64Projection() throws {
        let text = try text()
        let nearOne = text.replacingOccurrences(of: #""formatVersion":1"#, with: #""formatVersion":1.00000000000000000001"#)
        XCTAssertNotEqual(nearOne, text)
        XCTAssertEqual(try LocalizedStringLoader.parseStringsManifest(nearOne).formatVersion, 1)
        let size = text.replacingOccurrences(of: #""url":"en.json""#, with: #""decodedBytes":9007199254740990.9,"url":"en.json""#)
        XCTAssertNotEqual(size, text)
        XCTAssertEqual(try LocalizedStringLoader.parseStringsManifest(size).files["en"]?.decodedBytes, 9_007_199_254_740_991)
    }
    func testSemanticEntryOrderAndNativeTypedProjectionOrder() throws {
        let base = try manifest()
        let file: StringsManifestValue = .object([.init(name: "url", value: .string("")), .init(name: "sha256", value: .string(String(repeating: "a", count: 64)))])
        guard case .object(var members) = base.decodedValue else { return XCTFail("fixture shape") }
        members.removeAll { $0.name == "files" }
        members.append(.init(name: "files", value: .object([.init(name: "fr", value: file), .init(name: "en", value: file)])))
        XCTAssertThrowsError(try LocalizedStringLoader.validateStringsManifest(.object(members))) {
            XCTAssertEqual(($0 as? ConfigurationError)?.message, "The manifest entry for 'fr' must carry a non-empty url")
        }
        let typed = StringsManifestV1(catalogVersion: "v1", catalogFingerprint: base.catalogFingerprint, fallbackLocale: "en", baseUrl: base.baseUrl,
            files: ["fr": .init(url: "", sha256: String(repeating: "a", count: 64)), "en": .init(url: "", sha256: String(repeating: "a", count: 64))])
        XCTAssertThrowsError(try LocalizedStringLoader.validateStringsManifest(typed)) {
            XCTAssertEqual(($0 as? ConfigurationError)?.message, "The manifest entry for 'en' must carry a non-empty url")
        }
    }
    func testDuplicateDiagnosticPathIsUTF16Bounded() throws {
        let name = String(repeating: "a", count: 5_000)
        let json = "{\"" + name + "\":{\"x\":1,\"x\":2}}"
        XCTAssertThrowsError(try LocalizedStringLoader.parseStringsManifest(json, source: "wire")) {
            let error = $0 as? StringsParseError
            let path = error?.message.components(separatedBy: " encountered at ").last
            XCTAssertEqual(path?.utf16.count, 4_096)
            XCTAssertTrue(path?.hasSuffix("…") == true)
            XCTAssertNil(error?.path)
        }
    }
}
