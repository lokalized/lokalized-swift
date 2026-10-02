import XCTest
@testable import Lokalized

final class IDNACompatibilityNormalizationTests: XCTestCase {
    func testPrecomposedAndDecomposedContextsRemainDistinctInURLProfile() {
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0xE9, 0x323]), [0xE9, 0x323])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0x65, 0x301, 0x323]), [0x1EB9, 0x301])
        XCTAssertEqual(PinnedNFC.normalize([0xE9, 0x323]), [0x1EB9, 0x301])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0x1E0B, 0x323]), [0x1E0B, 0x323])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0x64, 0x307, 0x323]), [0x1E0D, 0x307])
    }
    func testNewCombiningClassesRemainUnknownToLegacyOrdering() {
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0x61, 0x897, 0x64E]), [0x61, 0x897, 0x64E])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0x61, 0x1ACF, 0x323]), [0x61, 0x1ACF, 0x323])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0x61, 0x301, 0x323]), [0x1EA1, 0x301])
    }
    func testSlowPathNormalizesAcrossLabelBoundaries() {
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0xE9, 0x323, 0x2E, 0x61, 0x301]), [0x1EB9, 0x301, 0x2E, 0xE1])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0xE9, 0x323, 0x2E, 0x628, 0x323, 0x301]), [0xE9, 0x323, 0x2E, 0x628, 0x323, 0x301])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0xAC00, 0x11A8, 0x2E, 0x61, 0x301]), [0xAC01, 0x2E, 0xE1])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0xE9, 0x323, 0x2E, 0xAC01, 0x11A8]), [0x1EB9, 0x301, 0x2E, 0xAC01, 0x11A8])
    }
    func testAdjacentHangulJamoAndExistingSyllablesUseObservedProfile() {
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0x1100, 0x1161, 0x11A8]), [0xAC01])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0x1112, 0x1175, 0x11C2]), [0xD7A3])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0xAC00, 0x11A8]), [0xAC00, 0x11A8])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0xAC01, 0x11A8]), [0xAC01, 0x11A8])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0x1100, 0x301, 0x1161]), [0x1100, 0x301, 0x1161])
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize([0x1100, 0x1161, 0x11A8, 0x11A8]), [0xAC01, 0x11A8])
    }
    func testLongDisorderedRunHasStableOrdering() {
        let count = 10_000
        let input: [UInt32] = (0..<count).flatMap { _ -> [UInt32] in [UInt32(0x301), UInt32(0x323)] }
        XCTAssertEqual(IDNACompatibilityNormalizer.normalize(input), Array(repeating: UInt32(0x323), count: count) + Array(repeating: UInt32(0x301), count: count))
    }
}
