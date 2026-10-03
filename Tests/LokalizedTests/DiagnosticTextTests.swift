import Foundation
import XCTest
import LokalizedConformanceSupport

final class DiagnosticTextTests: XCTestCase {
    private var reference: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Reference", isDirectory: true)
    }
    func testSharedPublicParserDiagnostics() throws {
        let report = try DiagnosticTextQualification.run(referenceDirectory: reference)
        XCTAssertEqual(report.totalCases, 36)
        XCTAssertEqual(report.observations.count, 36)
        XCTAssertTrue(report.failed.isEmpty, report.failed.map { $0.id + ": " + $0.detail }.joined(separator: "\n"))
        XCTAssertEqual(report.status, "passed")
    }
    func testAlteredFixtureRefusedBeforeExecution() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var data = try Data(contentsOf: reference.appendingPathComponent("diagnostic-text-v1.1.json"))
        data.append(0x20)
        try data.write(to: directory.appendingPathComponent("diagnostic-text-v1.1.json"))
        XCTAssertThrowsError(try DiagnosticTextQualification.run(referenceDirectory: directory)) { error in
            XCTAssertTrue(String(describing: error).contains("artifact digest differs"))
        }
    }
}
