import Foundation
import XCTest
@testable import Lokalized
@testable import LokalizedConformanceSupport

final class LanguageRangeTests: XCTestCase {
    func testNativeStandaloneQualification() throws {
        XCTAssertEqual(try LanguageRangeQualification.run(), 29)
    }

    func testAllPinnedParserConstructorAndUnicodeGoldens() throws {
        struct Entry: Decodable { let mode: String; let text: String; let weightBits: String; let result: String }
        struct Archive: Decodable { let formatVersion: Int; let jdkReleaseSHA256: String; let samples: [Entry] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: root.appendingPathComponent("Reference/language-range-goldens.json")))
        XCTAssertEqual(archive.formatVersion, 1)
        XCTAssertEqual(archive.jdkReleaseSHA256, "31c8dd26f07b2bd2c394663b57a93879ea139f525c76c730b13956890c151239")
        XCTAssertEqual(archive.samples.count, 3663)
        for entry in archive.samples {
            let actual: String
            do {
                switch entry.mode {
                case "constructor":
                    actual = "C\t" + member(try LanguageRange(entry.text, weight: Double(bitPattern: try XCTUnwrap(UInt64(entry.weightBits, radix: 16)))))
                case "iana", "jdk":
                    actual = "P\t" + (try LanguageRangeParser.parse(entry.text, equivalents: entry.mode == "jdk" ? .jdk : .ianaRegistry)).map(member).joined(separator: ",")
                case "lowercase": actual = "L\t" + hex(LanguageRangeLowercase.apply(entry.text))
                case "weight": actual = "W\t" + bits(try XCTUnwrap(LanguageRangeWeight.parse(entry.text)))
                default: return XCTFail("Unknown golden operation: \(entry.mode)")
                }
            } catch let error as LanguageRangeError {
                actual = "E\t" + (error.kind == .indexOutOfBounds ? "ArrayIndexOutOfBoundsException" : "IllegalArgumentException") + "\t" + hex(error.message)
            }
            XCTAssertEqual(actual, entry.result, "\(entry.mode) \(entry.text.debugDescription) weightbits=\(entry.weightBits)")
        }
    }

    func testEveryCompiledDataMappingAndPropertyBoundary() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Reference/jdk-language-range-data.json"))) as? [String: Any])
        let mappings = try XCTUnwrap(fields["scalarLowercase"] as? [[Any]])
        XCTAssertEqual(mappings.count, 1433)
        for mapping in mappings {
            let key = try XCTUnwrap(mapping[0] as? UInt32), values = try XCTUnwrap(mapping[1] as? [UInt32])
            XCTAssertEqual(LanguageRangeTables.lowercase(key), values)
        }
        let ranges = try XCTUnwrap(fields["wordPropertyRanges"] as? [[UInt32]])
        XCTAssertEqual(ranges.count, 1376)
        var previous: UInt32 = 0
        for range in ranges {
            XCTAssertEqual(LanguageRangeTables.wordProperties(range[0]), range[2])
            XCTAssertEqual(LanguageRangeTables.wordProperties(range[1]), range[2])
            if range[0] > previous + 1 { XCTAssertEqual(LanguageRangeTables.wordProperties(range[0] - 1), 0) }
            previous = range[1]
        }
        for scalar: UInt32 in [0xd800, 0xdfff, 0x110000] {
            XCTAssertNil(LanguageRangeTables.lowercase(scalar))
            XCTAssertEqual(LanguageRangeTables.wordProperties(scalar), 0)
        }
    }

    private func member(_ range: LanguageRange) -> String { hex(range.range) + "@" + bits(range.weight) }
    private func bits(_ value: Double) -> String { let text = String(value.bitPattern, radix: 16); return String(repeating: "0", count: 16 - text.count) + text }
    private func hex(_ value: String) -> String { value.utf8.map { let text = String($0, radix: 16); return text.count == 1 ? "0" + text : text }.joined() }
}
