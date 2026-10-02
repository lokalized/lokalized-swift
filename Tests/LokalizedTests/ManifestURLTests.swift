import Foundation
import XCTest
@testable import Lokalized
import LokalizedConformanceSupport

final class ManifestURLTests: XCTestCase {
    func testPinnedIndependentNodeURLArchive() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let report = try ConformanceRunner.manifestURLAudit(referenceDirectory: root.appendingPathComponent("Reference"))
        XCTAssertEqual(report.total, 3_479); XCTAssertEqual(report.qualified, 3_479)
        XCTAssertEqual(report.runtimePassed, 3_479); XCTAssertEqual(report.qualifiedIDs.count, 3_479)
        XCTAssertEqual(report.pendingNativeCapability, 0); XCTAssertEqual(report.failed, 0, report.failures.joined(separator: ", "))
        XCTAssertEqual(report.qualifiedIDSetSHA256, "745c8687ac0a666e71d7cb163bc2734cc1b6d039363b7748fc341d630f360bed")
        XCTAssertEqual(report.pendingIDSetSHA256, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(report.unicodeDomains.total, 56_513)
        XCTAssertEqual(report.unicodeDomains.runtimePassed, 56_513)
        XCTAssertEqual(report.unicodeDomains.failed, 0, report.unicodeDomains.failures.joined(separator: ", "))
        XCTAssertEqual(report.unicodeDomains.qualifiedIDSetSHA256, "c9c6944a8e63b3d92680f19fd53c3a1f4ee871db10efca26183a2ead699a9432")
        XCTAssertEqual(report.unicodeDomains.excludedIllFormedSourceLines, [548, 549])
        XCTAssertEqual(report.unicodeDomains.propertyDiscriminantRows, 32_203)
        XCTAssertEqual(report.unicodeDomains.normalizationDiscriminantRows, 17_062)
        XCTAssertEqual(report.unicodeDomains.normalizationProfileSHA256, "9cb7782123a2f08f8a69a8ec702ff7910cff69cd03773e6d665d79ed5a4b327c")
        XCTAssertEqual(report.unicodeDomains.oracleRuntimeLockSHA256, "e0fa1af12b31b3750be894db9a892775b672e5d2577923b84e7c83154130cb1d")
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
    func testUnicodeDomainsUsePinnedMappingNormalizationAndPunycode() throws {
        XCTAssertEqual(try ManifestURL.resolve("https://é.example/a"), "https://xn--9ca.example/a")
        XCTAssertEqual(try ManifestURL.resolve("https://%C3%A9.example/a"), "https://xn--9ca.example/a")
        XCTAssertEqual(try ManifestURL.resolve("https://e\u{0301}.example/a"), "https://xn--9ca.example/a")
        XCTAssertEqual(try ManifestURL.resolve("https://XN--CAF-DMA.example/a"), "https://xn--caf-dma.example/a")
        XCTAssertEqual(try ManifestURL.resolve("a", relativeTo: "https://é.example/"), "https://xn--9ca.example/a")
        XCTAssertEqual(try ManifestURL.resolve("https://faß.de/"), "https://xn--fa-hia.de/")
        XCTAssertEqual(try ManifestURL.resolve("https://ｅｘａｍｐｌｅ。ｃｏｍ/"), "https://example.com/")
        XCTAssertEqual(try ManifestURL.resolve("https://🫩.example/"), "https://xn--b39h.example/")
        for reference in ["https://é.example/", "https://%C3%A9.example/", "https://XN--CAF-DMA.example/", "https://a\u{200D}.example/"] {
            XCTAssertNil(ManifestURL.unqualifiedFeature(reference: reference))
        }
    }
    func testBrowserIDNAProfileRetainsRelaxedASCIIAndRejectsInvalidUnicodeLabels() throws {
        for label in ["xn--", "xn--a", "xn--abc-", "xn--0", "-a", "ab--cd", "a" + String(repeating: "b", count: 64)] {
            XCTAssertEqual(try ManifestURL.resolve("https://" + label + ".example/"), "https://" + label + ".example/")
        }
        XCTAssertEqual(try ManifestURL.resolve("https://1.א/"), "https://1.xn--4db/")
        XCTAssertEqual(try ManifestURL.resolve("https://_a.א/"), "https://_a.xn--4db/")
        XCTAssertEqual(try ManifestURL.resolve("https://क्\u{200D}ष.example/"), "https://xn--11b2ezcw70k.example/")
        for reference in ["https://é.xn--/", "https://a\u{200C}.example/", "https://a\u{200D}.example/",
                          "https://\u{0903}.example/", "https://1א.example/", "https://אa.example/", "https://%ED%A0%80/", "https://%F4%90%80%80/",
                          "https://\u{FEFF}xn--0/", "https://%EF%BB%BFxn--0/"] {
            XCTAssertThrowsError(try ManifestURL.resolve(reference)) { XCTAssertEqual(($0 as? ManifestURL.Failure)?.kind, .invalidURL) }
        }
    }
    func testUnicodeDomainBudgetUsesDecodedBytesBeforeIgnoringCharacters() throws {
        let below = String(repeating: "b", count: 16_381)
        XCTAssertEqual(try ManifestURL.resolve("https://" + below + "\u{FEFF}/"), "https://" + below + "/")
        XCTAssertEqual(try ManifestURL.resolve("https://" + below + "%EF%BB%BF/"), "https://" + below + "/")
        XCTAssertEqual(try ManifestURL.resolve("next", relativeTo: "https://" + below + "%EF%BB%BF/"), "https://" + below + "/next")
        for suffix in ["\u{FEFF}", "%EF%BB%BF"] {
            XCTAssertThrowsError(try ManifestURL.resolve("https://" + String(repeating: "b", count: 16_382) + suffix + "/")) {
                XCTAssertEqual(($0 as? ManifestURL.Failure)?.kind, .invalidURL)
            }
        }
        let ascii = String(repeating: "b", count: 20_000) + ".example"
        XCTAssertEqual(try ManifestURL.resolve("https://" + ascii + "/"), "https://" + ascii + "/")
        let escapedASCII = "%62" + String(repeating: "b", count: 16_383)
        XCTAssertEqual(try ManifestURL.resolve("https://" + escapedASCII + "/"), "https://" + String(repeating: "b", count: 16_384) + "/")
        XCTAssertThrowsError(try ManifestURL.resolve("https://" + escapedASCII + "b/")) {
            XCTAssertEqual(($0 as? ManifestURL.Failure)?.kind, .invalidURL)
        }
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
    func testIDNAArchiveDigestTamperingRefusesBeforeObservations() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        // A complete, CRC-valid gzip member containing different JSON bytes:
        // the unchanged decoded archive digest must refuse it before parsing.
        let bytes = try XCTUnwrap(Data(base64Encoded: "H4sIAAAAAAAC/6uu5QIABrCh3QMAAAA="))
        try bytes.write(to: scratch.appendingPathComponent("manifest-idna-goldens.json.gz"))
        XCTAssertThrowsError(try ConformanceRunner.manifestIDNAAudit(referenceDirectory: scratch)) {
            XCTAssertEqual(($0 as? ConformanceError)?.description, "Manifest IDNA archive digest differs")
        }
    }
}
