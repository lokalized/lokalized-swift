import CryptoKit
import Foundation
import XCTest
import Lokalized
@testable import LokalizedConformanceSupport

final class LoaderAdapterTests: XCTestCase {
    private var reference: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Reference", isDirectory: true)
    }
    func testFrozenFilesystemObservationsAndUnresolvedCarriers() throws {
        let report = try LoaderQualification.run(referenceDirectory: reference)
        XCTAssertEqual(report.scope, "native-filesystem-full-observation")
        XCTAssertEqual(report.status, "passed")
        XCTAssertEqual(report.eligibleIDs.count, 145)
        XCTAssertEqual(report.runtimePassed, report.eligibleIDs)
        XCTAssertEqual(report.eligibleIDsSHA256, "6c6043d0326a9a524690c485292cc2cd748161504fbaa5c0c7fcb97d91e16991")
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertEqual(report.pendingCarriers.count, 164)
        XCTAssertEqual(report.pendingCarriers.filter { $0.category.hasPrefix("jvm-") }.count, 159)
        XCTAssertEqual(report.adaptationObservations.count, 5)
        XCTAssertTrue(report.adaptationObservations.allSatisfy { $0.difference == "String code units differ at $.load.failureMessage" })
        let ids = report.adaptationObservations.map(\.id).sorted()
        let digest = SHA256.hash(data: Data(ids.map { $0 + "\n" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "f2e4b155d9ff9f7a77acf00a53fcead51f8482fce9e47230466543a51f779131")
    }
    func testNativeLoadedSnapshotsAndDeterministicDiagnosticOrder() throws {
        XCTAssertEqual(try LoaderQualification.runNative(), 12)
    }
    func testNativeBundleResourceAndFilenameBoundaries() throws {
        let report = try LoaderBoundaryQualification.run()
        XCTAssertEqual(report.status, "passed")
        XCTAssertEqual(report.passed.count, 20)
        XCTAssertEqual(Set(report.passed), Set(report.observations.keys))
    }
    func testExpectedFieldsCannotConfigureActualLoad() throws {
        let corpus = try ConformanceRunner.load(referenceDirectory: reference)
        let row = try XCTUnwrap(corpus.cases.first { $0.id == "loader-smoke.load.clean-directory-reports-locales-and-keys" })
        let session = LoaderObservations.Session()
        let actual = try session.execute(row)
        let forged = BehavioralCase(id: "native.loader.forged-expected", operation: row.operation, partition: row.partition,
            input: row.input, expected: .object([.test("load", .object([.test("failed", .bool(true))]))]),
            fixture: row.fixture, materializedFiles: row.materializedFiles, fixtureID: row.fixtureID)
        let repeated = try session.execute(forged)
        XCTAssertNil(try JSONComparison.firstDifference(expected: actual, actual: repeated))
        XCTAssertNotNil(try JSONComparison.firstDifference(expected: forged.expected, actual: repeated))
        guard case .object(let input) = row.input else { return XCTFail("Load input is not an object") }
        let unknown = BehavioralCase(id: "native.loader.unknown-input", operation: row.operation, partition: row.partition,
            input: .object(input + [.test("futureTransport", .bool(true))]), expected: row.expected,
            fixture: row.fixture, materializedFiles: row.materializedFiles, fixtureID: row.fixtureID)
        XCTAssertThrowsError(try session.execute(unknown)) { XCTAssertTrue($0 is ConformanceError) }
    }
    func testPendingDiagnosticOrderGuardsUseInputsAndAreNarrow() throws {
        let corpus = try ConformanceRunner.load(referenceDirectory: reference)
        let row = try XCTUnwrap(corpus.cases.first { $0.id == "classpath-filenames.warn.two-invalid-json-filesystem" })
        let renamed = BehavioralCase(id: "native.loader.competing-names", operation: row.operation, partition: row.partition,
            input: row.input, expected: .object([]), fixture: row.fixture, materializedFiles: row.materializedFiles, fixtureID: row.fixtureID)
        XCTAssertEqual(try LoaderObservations.pendingAdaptations(renamed).map(\.category), ["native-competing-invalid-json-filenames"])
        XCTAssertNil(try ConformanceRunner.execute(renamed))
        for id in ["classpath-filenames.duplicate.case-collision-filesystem", "dedup-and-candidates.collision.he-and-iw-filenames", "locale-identity.filename.grandfathered-duplicate-fails-the-load"] {
            let duplicate = try XCTUnwrap(corpus.cases.first { $0.id == id })
            XCTAssertTrue(try LoaderObservations.pendingAdaptations(duplicate).isEmpty, id)
            XCTAssertNotNil(try ConformanceRunner.execute(duplicate), id)
        }
    }
}
