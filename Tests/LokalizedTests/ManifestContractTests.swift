import Foundation
import CryptoKit
import XCTest
@testable import Lokalized
@testable import LokalizedConformanceSupport

final class ManifestContractTests: XCTestCase {
    private var reference: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Reference", isDirectory: true)
    }

    func testVersionedNativeManifestContractObservations() throws {
        let report = try ManifestContractQualification.run(referenceDirectory: reference)
        XCTAssertEqual(report.totalCases, 499)
        XCTAssertEqual(report.historicalAgreementIDs.count, 464)
        XCTAssertEqual(report.archiveCorrectionIDs.count, 4)
        XCTAssertEqual(report.behaviorProfileVersion, "1.1.0")
        XCTAssertEqual(report.eligibleIDs.count, 468)
        XCTAssertEqual(report.pendingCarriers.count, 31)
        XCTAssertEqual(report.runtimePassed, report.eligibleIDs)
        XCTAssertEqual(report.eligibleIDsSHA256, "f8062a5ef05939d4100f68b1a1c64ab351632992a56719154831e5c1babb69c1")
        XCTAssertEqual(report.strictNativeEqualIDs.count, 162)
        XCTAssertEqual(report.projectedMatchedIDs.count, 306)
        XCTAssertEqual(digestIDs(report.strictNativeEqualIDs), "8173cf865643f95030aa34f52dfc014d81cc65e2d055cdf09f148140a8759e16")
        XCTAssertEqual(digestIDs(report.projectedMatchedIDs), "c4d1fdc893f09153a3acb72b96b413daea5ef8df2c753d10220897fe80e351ab")
        XCTAssertEqual(digestIDs(report.pendingCarriers.map(\.id)), "c6157779eb161a1e0193b8abc246bc80112e3ba67e27d0f296d3722006f481f4")
        XCTAssertEqual(report.observations.map(\.id), report.eligibleIDs)
        XCTAssertEqual(report.adaptationObservations.map(\.id), report.projectedMatchedIDs)
        XCTAssertEqual(report.pendingObservations.map(\.id), report.pendingCarriers.map(\.id))
        XCTAssertFalse(report.nativeMappingsRatified)
        XCTAssertTrue(report.failed.isEmpty, report.failed.prefix(20).map { $0.id + ": " + $0.detail }.joined(separator: "\n"))
        XCTAssertEqual(report.status, "passed")
    }

    func testArchivePinRefusesChangedBytesBeforeExecution() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var bytes = try Data(contentsOf: reference.appendingPathComponent("manifest-contract-vectors.json"))
        bytes.append(0x20)
        try bytes.write(to: directory.appendingPathComponent("manifest-contract-vectors.json"))
        XCTAssertThrowsError(try ManifestContractQualification.load(referenceDirectory: directory)) { error in
            XCTAssertTrue(String(describing: error).contains("archive digest differs"))
        }
    }

    func testUnicodeDomainsExecuteThroughTheNativeManifestContract() throws {
        let original = try XCTUnwrap(ManifestContractQualification.load(referenceDirectory: reference).first { $0.id == "m7a.validate.valid" })
        let text = try original.input.string("manifestJSON", at: original.id)
        for url in ["https://é.example/v1/", "https://xn--bcher-kva.example/v1/"] {
            var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            value["baseUrl"] = url
            let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            let input: [ExactString: JSONValue] = ["manifestJSON": .string(String(decoding: bytes, as: UTF8.self))]
            let row = ManifestContractQualification.Row(id: "native.unicode-url", operation: "validateStringsManifest", input: input, expected: .null)
            guard case .observed(let native, _, let rules) = try ManifestContractQualification.execute(row) else { return XCTFail("Unicode URL validation must execute") }
            XCTAssertTrue(rules.isEmpty)
            let observation = try native.checkedObject(at: "actual")
            XCTAssertEqual(try observation.string("outcome", at: "actual"), "returned")
            let manifest = try observation.value("value", at: "actual").checkedObject(at: "actual.value")
            XCTAssertEqual(try manifest.string("baseUrl", at: "actual.value"), url)

            value["formatVersion"] = 2
            let earlierBytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            let earlier = ManifestContractQualification.Row(id: "native.earlier-refusal", operation: "validateStringsManifest",
                input: ["manifestJSON": .string(String(decoding: earlierBytes, as: UTF8.self))], expected: .null)
            guard case .observed(let earlierNative, _, let earlierRules) = try ManifestContractQualification.execute(earlier) else { return XCTFail("An earlier actual validation refusal must execute") }
            XCTAssertEqual(earlierRules, ["native-configuration-error-envelope"])
            let earlierError = try earlierNative.checkedObject(at: "earlier").value("error", at: "earlier").checkedObject(at: "earlier.error")
            guard case .null = earlierError["cause"] else { return XCTFail("Earlier refusal must have no URL capability cause") }
        }
    }

    private func digestIDs(_ ids: [String]) -> String {
        SHA256.hash(data: Data(ids.map { $0 + "\n" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
