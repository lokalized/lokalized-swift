import Foundation
import XCTest
@testable import Lokalized
@testable import LokalizedConformanceSupport

final class ManifestNormalizationTests: XCTestCase {
    private var reference: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Reference")
    }
    func testSharedPublicDoorAndCoreSeparationCases() throws {
        let report = try ManifestNormalizationQualification.run(referenceDirectory: reference)
        XCTAssertEqual(report.totalCases, 35)
        XCTAssertEqual(report.passedIDs.count, 35)
        XCTAssertEqual(report.observations.count, 35)
        XCTAssertTrue(report.failed.isEmpty, report.failed.map { $0.id + ": " + $0.detail }.joined(separator: "\n"))
    }
    func testAlteredProfileBytesAreRefusedBeforeExecution() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var data = try Data(contentsOf: reference.appendingPathComponent("manifest-normalization-v1.1.json"))
        data.append(0x20)
        try data.write(to: directory.appendingPathComponent("manifest-normalization-v1.1.json"))
        XCTAssertThrowsError(try ManifestNormalizationQualification.run(referenceDirectory: directory)) { error in
            XCTAssertTrue(String(describing: error).contains("profile digest differs"))
        }
    }
    func testExpectedValuesCannotConfigureRoundTripExecution() throws {
        let data = try Data(contentsOf: reference.appendingPathComponent("manifest-normalization-v1.1.json"))
        let profile = try JSONReader.parse(data, limits: ConformanceRunner.corpusLimits).checkedObject(at: "profile")
        guard case .array(let rows) = profile["cases"] else { return XCTFail("Missing cases") }
        let fields = try XCTUnwrap(rows.first { value in
            (try? value.checkedObject(at: "case").string("id", at: "case")) == "m8k.round-trip.upper"
        }).checkedObject(at: "case")
        let input = try fields.value("input", at: "case").checkedObject(at: "input")
        let baseline = try ManifestNormalizationQualification.execute(.init(id: "guard.round-trip", operation: "roundTrip", input: input, expected: .null))
        for expected in [JSONValue.bool(false), .string("invented"), .object([.test("outcome", .string("threw"))])] {
            let actual = try ManifestNormalizationQualification.execute(.init(id: "guard.round-trip", operation: "roundTrip", input: input, expected: expected))
            guard case .observed(let first, _, _) = baseline, case .observed(let second, _, _) = actual else { return XCTFail("Actual operations must run") }
            XCTAssertNil(try JSONComparison.firstDifference(expected: first, actual: second))
        }
    }
}
