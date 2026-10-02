import Foundation
import XCTest
import Lokalized
@testable import LokalizedConformanceSupport

final class RuntimeAdapterTests: XCTestCase {
    private var reference: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Reference", isDirectory: true)
    }

    func testFrozenRuntimeFullObservationsAndPendingGuards() throws {
        let report = try RuntimeAdapterQualification.run(referenceDirectory: reference)
        XCTAssertEqual(report.scope, "public-runtime-full-observation")
        XCTAssertEqual(report.status, "passed")
        XCTAssertEqual(report.totalRuntimeCases, 1_452)
        XCTAssertEqual(report.eligibleIDs.count, 1_432)
        XCTAssertEqual(report.eligibleIDsSHA256, "364e6f0954c2adc1c825a86aee4ea9b423fb850e741b13a01cb2973b6a1a6b60")
        XCTAssertEqual(report.runtimePassed, report.eligibleIDs)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertEqual(report.pending.count, 20)
        XCTAssertTrue(report.pending.allSatisfy { !$0.guards.isEmpty })
        XCTAssertFalse(report.nativeMappingsRatified)
    }

    func testExpectedFieldsCannotConfigureExecutionOrInventChannels() throws {
        let corpus = try ConformanceRunner.load(referenceDirectory: reference)
        let row = try XCTUnwrap(corpus.cases.first { $0.id == "failure-handler.control.get-on-present-key-returns-translation" })
        let session = RuntimeObservations.Session()
        let actual = try XCTUnwrap(session.execute(row))
        let forged = BehavioralCase(id: "native.adapter.forged-expectation", operation: row.operation, partition: row.partition,
            input: row.input, expected: .object([.test("translation", .string("manufactured from expected"))]),
            fixture: row.fixture, materializedFiles: row.materializedFiles)
        let repeated = try XCTUnwrap(session.execute(forged))
        XCTAssertNil(try JSONComparison.firstDifference(expected: actual, actual: repeated))
        XCTAssertNotNil(try JSONComparison.firstDifference(expected: forged.expected, actual: repeated))
        guard case .object(let members) = actual else { return XCTFail("Runtime observation is not an object") }
        let inventedChannel = JSONValue.object(members + [.test("resolverCalls", .array([]))])
        XCTAssertNotNil(try JSONComparison.firstDifference(expected: inventedChannel, actual: repeated))
    }

    func testUnknownInputsAreAuthoringErrorsAndNeverRuntimeThrows() throws {
        let corpus = try ConformanceRunner.load(referenceDirectory: reference)
        let row = try XCTUnwrap(corpus.cases.first { $0.id == "failure-handler.control.get-on-present-key-returns-translation" })
        guard case .object(let input) = row.input else { return XCTFail("Runtime input is not an object") }
        let malformed = BehavioralCase(id: "native.adapter.unknown-input", operation: row.operation, partition: row.partition,
            input: .object(input + [.test("futureOverride", .bool(true))]), expected: row.expected,
            fixture: row.fixture, materializedFiles: row.materializedFiles)
        XCTAssertThrowsError(try RuntimeObservations.execute(malformed)) { error in
            XCTAssertTrue(error is ConformanceError)
            XCTAssertTrue(String(describing: error).contains("Unknown field"))
        }
        let malformedNullCallback = BehavioralCase(id: "native.adapter.unknown-null-callback-field", operation: row.operation, partition: row.partition,
            input: .object(input + [.test("translationFailureHandler", .object([
                .test("behavior", .string("return-null")), .test("futureCallbackField", .bool(true))
            ]))]), expected: row.expected, fixture: row.fixture, materializedFiles: row.materializedFiles)
        XCTAssertThrowsError(try RuntimeObservations.execute(malformedNullCallback)) { error in
            XCTAssertTrue(error is ConformanceError)
            XCTAssertTrue(String(describing: error).contains("Unknown field"))
        }
    }

    func testFiniteResolverMappingsStayExecutableAndMissingActualMappingStaysPending() throws {
        let corpus = try ConformanceRunner.load(referenceDirectory: reference)
        let known = try XCTUnwrap(corpus.cases.first { $0.id == "phonetic-resolver.constants.vowel" })
        let absent = try XCTUnwrap(corpus.cases.first { $0.id == "phonetic-resolver.constants.unmapped-term-returns-null" })
        let session = RuntimeObservations.Session()
        XCTAssertNotNil(try session.execute(known))
        XCTAssertTrue(session.pendingGuards.isEmpty)
        // Renaming the case and forging an expected success do not change its
        // disposition; the actual callback sees the absent mapping/default.
        let renamed = BehavioralCase(id: "native.adapter.unmapped-phonetic", operation: absent.operation, partition: absent.partition,
            input: absent.input, expected: known.expected, fixture: absent.fixture, materializedFiles: absent.materializedFiles)
        XCTAssertNil(try session.execute(renamed))
        XCTAssertEqual(session.pendingGuards.map(\.category), ["phonetic-unmapped-null-return"])
        XCTAssertTrue(session.pendingGuards[0].evidence.contains("Actual by-term consultation"))
        XCTAssertNotNil(try session.execute(known))
        XCTAssertTrue(session.pendingGuards.isEmpty)
    }
}
