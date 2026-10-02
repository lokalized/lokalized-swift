import Foundation
import CryptoKit
import XCTest
import Lokalized
@testable import LokalizedConformanceSupport

final class ConformanceTests: XCTestCase {
    func testStandaloneQualificationChecks() throws {
        XCTAssertGreaterThan(try ConformanceRunner.selfTest(), 90)
    }

    func testPinnedCorpusAccountingAndActualForms() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let reference = root.appendingPathComponent("Reference", isDirectory: true)
        let inventory = try ConformanceRunner.inventory(referenceDirectory: reference)
        XCTAssertEqual(inventory.totalCases, 2_381)
        XCTAssertEqual(inventory.fixtures, 586)
        XCTAssertEqual(inventory.requiredPortable, 2_155)
        XCTAssertEqual(inventory.informational, 226)
        XCTAssertEqual(inventory.operations.count, 18)
        let audit = try ConformanceRunner.audit(referenceDirectory: reference)
        XCTAssertEqual(audit.status, "incomplete")
        XCTAssertEqual(audit.runtimePassed.count, 2_197)
        XCTAssertTrue(audit.runtimePassed.contains("language-forms.tuples.all-61-axis-name-render-name"))
        XCTAssertEqual(audit.unimplemented.count, 184)
        let passingDigest = SHA256.hash(data: Data(audit.runtimePassed.sorted().map { $0 + "\n" }.joined().utf8))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(passingDigest, "2c4848b0b481d01523e11813efbf5dd874cc5c75ca8b15aaa41e5ff5f25ee76f")
        XCTAssertTrue(audit.failed.isEmpty)
        XCTAssertTrue(audit.nativeRepresentationMapped.isEmpty)
    }

    func testTamperedCorpusIsRejectedBeforeExecution() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data("{}".utf8).write(to: temporary.appendingPathComponent("behavioral-vectors.json"))
        XCTAssertThrowsError(try ConformanceRunner.audit(referenceDirectory: temporary)) { error in
            XCTAssertTrue(String(describing: error).contains("digest"))
        }
    }

    func testTamperedMaterializedInputIsRejectedBeforeExecution() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let reference = root.appendingPathComponent("Reference", isDirectory: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for name in ["behavioral-vectors.json", "baseline.json"] {
            try FileManager.default.copyItem(at: reference.appendingPathComponent(name), to: temporary.appendingPathComponent(name))
        }
        try Data("{}".utf8).write(to: temporary.appendingPathComponent("materialized-fixtures.json"))
        XCTAssertThrowsError(try ConformanceRunner.audit(referenceDirectory: temporary)) { error in
            XCTAssertTrue(String(describing: error).contains("Materialized fixture digest"))
        }
    }

    func testFixtureStringificationKeepsExactUnicodeAndJSIndexOrdering() throws {
        let value = try JSONReader.parse(#"{"10":"ten","2":"two","é":"nfc","e\u0301":"nfd","controls":"\u0000\n\t"}"#)
        let bytes = try FixtureJSONWriter.bytes(value)
        let expected = "{\n  \"2\": \"two\",\n  \"10\": \"ten\",\n  \"é\": \"nfc\",\n  \"e\u{0301}\": \"nfd\",\n  \"controls\": \"\\u0000\\n\\t\"\n}\n"
        XCTAssertEqual(Array(bytes), Array(expected.utf8))
    }

    func testMetadataMatchesPinnedBuild() {
        let metadata = BuildMetadata.current
        XCTAssertEqual(metadata.producerImplementation, "lokalized-swift")
        XCTAssertEqual(metadata.cldrVersion, "48.2")
        XCTAssertEqual(metadata.behavioralVectorsVersion, "1.1.0")
        XCTAssertEqual(metadata.identifierUnicodeVersion, "15.0")
    }
}
