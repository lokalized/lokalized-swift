import Foundation
import XCTest
@testable import Lokalized
@testable import LokalizedConformanceSupport

final class ResolutionComponentTests: XCTestCase {
    func testNativeDiscriminators() throws {
        XCTAssertEqual(try ResolutionComponentQualification.runNative(), 16)
    }

    func testFrozenCorpusComponentProjection() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let report = try ResolutionComponentQualification.run(referenceDirectory: root.appendingPathComponent("Reference"))
        XCTAssertEqual(report.scope, "single-catalog-component-projection")
        XCTAssertEqual(report.totalCorpusCases, 2381)
        XCTAssertEqual(report.eligibleComponentIDs.count, 578)
        XCTAssertEqual(report.eligibleIDsSHA256, "fe8cbe90b8c000e88f094edb980b034ba86205ceeae65d6b460c2b825e24b467")
        XCTAssertTrue(report.failed.isEmpty, report.failed.map { $0.id + ": " + $0.detail }.joined(separator: "\n"))
        XCTAssertEqual(report.status, "passed")
        XCTAssertEqual(report.projectedComponentsPassed, report.eligibleComponentIDs)
        XCTAssertFalse(report.eligibleComponentIDs.isEmpty)
    }
}
