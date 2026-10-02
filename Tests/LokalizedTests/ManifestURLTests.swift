import Foundation
import XCTest
@testable import Lokalized
import LokalizedConformanceSupport

final class ManifestURLTests: XCTestCase {
    func testPinnedIndependentNodeURLArchive() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let report = try ConformanceRunner.manifestURLAudit(referenceDirectory: root.appendingPathComponent("Reference"))
        XCTAssertEqual(report.total, 3_479); XCTAssertEqual(report.qualified, 3_250)
        XCTAssertEqual(report.runtimePassed, 3_250); XCTAssertEqual(report.qualifiedIDs.count, 3_250)
        XCTAssertEqual(report.pendingNativeCapability, 229); XCTAssertEqual(report.failed, 0, report.failures.joined(separator: ", "))
        XCTAssertEqual(report.pendingIDSetSHA256, "6090d605bc5c52cbbab21d81ae3ad12135d2a9017f372cd66f10d9b9e44e1f50")
    }
    func testSeparatorsOperateOnUTF8NotExtendedGraphemeClusters() throws {
        let base = "https://host/a/b?q=x#f"
        XCTAssertEqual(try ManifestURL.resolve("#\u{0301}", relativeTo: base), "https://host/a/b?q=x#%CC%81")
        XCTAssertEqual(try ManifestURL.resolve("?\u{0301}", relativeTo: base), "https://host/a/b?%CC%81")
        XCTAssertEqual(try ManifestURL.resolve("/\u{0301}", relativeTo: base), "https://host/%CC%81")
        XCTAssertEqual(try ManifestURL.resolve("/a\u{0600}/b?x\u{0600}#y", relativeTo: base), "https://host/a%D8%80/b?x%D8%80#y")
        XCTAssertEqual(try ManifestURL.resolve("//host/\u{0301}", relativeTo: base), "https://host/%CC%81")
    }
    func testIPv6IsOriginalASCIIGrammarAndNeverCStringTruncation() throws {
        for input in ["https://[::1\0evil]/", "https://[::ffff:0192.0.2.1]/", "https://[1::2::3]/", "https://[1:2:3:4:5:6:7:8:9]/", "https://[::ffff:256.0.2.1]/"] {
            XCTAssertThrowsError(try ManifestURL.resolve(input)) { XCTAssertEqual(($0 as? ManifestURL.Failure)?.kind, .invalidURL) }
        }
        XCTAssertEqual(try ManifestURL.resolve("https://[::ffff:192.0.2.1]:443/a"), "https://[::ffff:c000:201]/a")
        XCTAssertEqual(try ManifestURL.resolve("https://[0:0:1:0:0:1:1:1]/"), "https://[::1:0:0:1:1:1]/")
    }
    func testPortParsingBoundedRegardlessOfLeadingZeroCount() throws {
        XCTAssertEqual(try ManifestURL.resolve("https://host:" + String(repeating: "0", count: 10_000) + "443/a"), "https://host/a")
        XCTAssertThrowsError(try ManifestURL.resolve("https://host:65536/"))
        XCTAssertEqual(try ManifestURL.resolve("http://host:65535/"), "http://host:65535/")
    }
    func testUnicodeDomainCapabilitiesAreExplicitAndInputDefined() {
        XCTAssertEqual(ManifestURL.unqualifiedFeature(reference: "https://é.example/a"), .unicodeDomain)
        XCTAssertEqual(ManifestURL.unqualifiedFeature(reference: "https://%C3%A9.example/a"), .unicodeDomain)
        XCTAssertEqual(ManifestURL.unqualifiedFeature(reference: "https://XN--CAF-DMA.example/a"), .punycodeDomain)
        XCTAssertEqual(ManifestURL.unqualifiedFeature(reference: "a", relativeTo: "https://é.example/"), .unicodeDomain)
        XCTAssertNil(ManifestURL.unqualifiedFeature(reference: "https://host/café?é#é"))
        XCTAssertNil(ManifestURL.unqualifiedFeature(reference: "https://%C3%28/"))
        XCTAssertThrowsError(try ManifestURL.resolve("https://é.example/")) { XCTAssertEqual(($0 as? ManifestURL.Failure)?.kind, .unsupportedFeature) }
    }
    func testArchiveDigestTamperingRefusesBeforeObservations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var bytes = try Data(contentsOf: root.appendingPathComponent("Reference/manifest-url-goldens.json")); bytes.append(32)
        try bytes.write(to: scratch.appendingPathComponent("manifest-url-goldens.json"))
        XCTAssertThrowsError(try ConformanceRunner.manifestURLAudit(referenceDirectory: scratch))
    }
}
