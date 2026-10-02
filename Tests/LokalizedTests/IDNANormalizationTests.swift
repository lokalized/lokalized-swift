import Foundation
import XCTest
@testable import Lokalized
import LokalizedConformanceSupport

final class IDNANormalizationTests: XCTestCase {
    func testCanonicalNormalizationAndCompatibilityPreservation() {
        XCTAssertEqual(PinnedNFC.normalize([]), [])
        XCTAssertEqual(PinnedNFC.normalize([0x65, 0x301]), [0xE9])
        XCTAssertEqual(PinnedNFC.normalize([0x212B]), [0xC5])
        XCTAssertEqual(PinnedNFC.normalize([0x1E0A, 0x323]), [0x1E0C, 0x307])
        XCTAssertEqual(PinnedNFC.normalize([0xFB01, 0xFF21]), [0xFB01, 0xFF21])
    }

    func testCompositionExclusionsAndEqualClassBlocking() {
        XCTAssertEqual(PinnedNFC.normalize([0x344]), [0x308, 0x301])
        XCTAssertEqual(PinnedNFC.normalize([0x41, 0x30B, 0x30A]), [0x41, 0x30B, 0x30A])
        XCTAssertEqual(PinnedNFC.normalize([0x300, 0x301, 0x323]), [0x323, 0x300, 0x301])
        XCTAssertEqual(PinnedNFC.normalize([0x41, 0x301, 0x30A]), [0xC1, 0x30A])
    }

    func testAlgorithmicHangulCompositionAndBoundaries() {
        XCTAssertEqual(PinnedNFC.normalize([0x1100, 0x1161]), [0xAC00])
        XCTAssertEqual(PinnedNFC.normalize([0x1100, 0x1161, 0x11A8]), [0xAC01])
        XCTAssertEqual(PinnedNFC.normalize([0xAC00, 0x11A8]), [0xAC01])
        XCTAssertEqual(PinnedNFC.normalize([0x1112, 0x1175, 0x11C2]), [0xD7A3])
        XCTAssertEqual(PinnedNFC.normalize([0x10FF, 0x1161, 0x11A8]), [0x10FF, 0x1161, 0x11A8])
        XCTAssertEqual(PinnedNFC.normalize([0x1100, 0x301, 0x1161]), [0x1100, 0x301, 0x1161])
        XCTAssertEqual(PinnedNFC.normalize([0xAC00, 0x11A7]), [0xAC00, 0x11A7])
    }

    func testLongDisorderedNonstarterRunPreservesStableOrdering() {
        let count = 10_000
        let input: [UInt32] = (0..<count).flatMap { _ -> [UInt32] in [UInt32(0x301), UInt32(0x323)] }
        XCTAssertEqual(PinnedNFC.normalize(input), Array(repeating: UInt32(0x323), count: count) + Array(repeating: UInt32(0x301), count: count))
    }

    func testEntireOfficialUnicode17NFCSuiteAndScalarIdentity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let report = try ConformanceRunner.idnaNormalizationAudit(referenceDirectory: root.appendingPathComponent("Reference"))
        XCTAssertEqual(report.status, "passed", report.failures.joined(separator: ", "))
        XCTAssertEqual(report.officialRows, 20_034)
        XCTAssertEqual(report.officialNFCEquations, 100_170)
        XCTAssertEqual(report.identityScalarChecks, 1_094_978)
        XCTAssertEqual(report.totalChecks, 1_195_148)
        XCTAssertEqual(report.passed, 1_195_148)
        XCTAssertEqual(report.failed, 0)
    }

    func testNormalizationArchiveTamperingRefusesBeforeQualification() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("Unicode-17.0.0"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var bytes = try Data(contentsOf: root.appendingPathComponent("Reference/Unicode-17.0.0/NormalizationTest.txt"))
        bytes.append(32)
        try bytes.write(to: scratch.appendingPathComponent("Unicode-17.0.0/NormalizationTest.txt"))
        XCTAssertThrowsError(try ConformanceRunner.idnaNormalizationAudit(referenceDirectory: scratch))
    }
}
