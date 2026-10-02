import Foundation
import XCTest
@testable import Lokalized
@testable import LokalizedConformanceSupport

final class ManifestContractGuardsTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)

    private func identityJSON(digest: String? = nil, version: String = "v1") -> String {
        #"{"formatVersion":1,"catalogVersion":""# + version + #"","resolvedFallbackLocale":"en","localeToSha256":{"en":""#
            + (digest ?? self.digest) + #""},"tiebreakerLocalesByLanguageCode":{}}"#
    }
    private func row(_ input: String, expected: JSONValue = .null, id: String = "guard.identity") -> ManifestContractQualification.Row {
        .init(id: id, operation: "computeCatalogIdentity", input: ["identityInputJSON": .string(input)], expected: expected)
    }
    private func observed(_ row: ManifestContractQualification.Row) throws -> (native: JSONValue, comparison: JSONValue, rules: [String]) {
        switch try ManifestContractQualification.execute(row) {
        case .observed(let native, let comparison, let rules): return (native, comparison, rules)
        case .pending(let reason, _): throw ConformanceError("Expected actual operation, received pending \(reason.category): \(reason.evidence)")
        }
    }
    private func same(_ left: JSONValue, _ right: JSONValue, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertNil(try JSONComparison.firstDifference(expected: left, actual: right), file: file, line: line)
    }

    func testExpectedPayloadDoesNotConfigureSuccessfulNativeExecution() throws {
        let input = identityJSON()
        let baseline = try observed(row(input))
        let native = try baseline.native.checkedObject(at: "native")
        XCTAssertEqual(try native.string("outcome", at: "native"), "returned")
        let value = try native.value("value", at: "native").checkedObject(at: "native.value")
        let actual = try value.value("identity", at: "native.value").checkedObject(at: "native.identity")
        let direct = try LocalizedStringLoader.computeCatalogIdentity(.init(catalogVersion: "v1", resolvedFallbackLocale: "en", localeToSha256: ["en": digest]))
        XCTAssertEqual(try actual.string("catalogFingerprint", at: "native.identity"), direct.catalogFingerprint)
        XCTAssertTrue(baseline.rules.isEmpty)
        try same(baseline.native, baseline.comparison)

        // Row execution receives expected only for later comparison. Deliberately
        // impossible oracle shapes cannot alter its inputs or returned behavior.
        let expectations: [JSONValue] = [
            .null, .bool(false), .array([.string("invented result")]),
            .object([.test("outcome", .string("threw")), .test("error", .object([.test("name", .string("InventedError")), .test("message", .string("do not execute"))]))]),
            .object([.test("outcome", .string("returned")), .test("value", .object([.test("catalogVersion", .string("wrong version")), .test("sha256", .string(String(repeating: "b", count: 64)))]))])
        ]
        for (index, expected) in expectations.enumerated() {
            let execution = try observed(row(input, expected: expected, id: "guard.identity.expected-\(index)"))
            try same(execution.native, baseline.native)
            try same(execution.comparison, baseline.comparison)
            XCTAssertEqual(execution.rules, baseline.rules)
        }
        let changedInput = try observed(row(identityJSON(version: "v2"), expected: baseline.native))
        XCTAssertNotNil(try JSONComparison.firstDifference(expected: baseline.native, actual: changedInput.native), "Actual input still controls identity")
    }

    func testMalformedTypedDigestRunsNativeRefusalBeforeExpectedComparison() throws {
        let malformed = "short"
        let directInput = CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en", localeToSha256: ["en": malformed])
        let direct: ConfigurationError
        do {
            _ = try LocalizedStringLoader.computeCatalogIdentity(directInput)
            return XCTFail("The real identity API must refuse a malformed digest")
        } catch let error as ConfigurationError { direct = error }
        XCTAssertEqual(direct.kind, .invalidArgument)
        XCTAssertNil(direct.cause)
        let fakeSuccess = JSONValue.object([.test("outcome", .string("returned")), .test("value", .null)])
        let baseline = try observed(row(identityJSON(digest: malformed), expected: fakeSuccess))
        let outer = try baseline.native.checkedObject(at: "native")
        XCTAssertEqual(try outer.string("outcome", at: "native"), "threw")
        let error = try outer.value("error", at: "native").checkedObject(at: "native.error")
        XCTAssertEqual(Set(error.keys), ["name", "message", "kind", "cause"])
        XCTAssertEqual(try error.string("name", at: "native.error"), "ConfigurationError")
        XCTAssertEqual(try error.string("kind", at: "native.error"), direct.kind.rawValue)
        XCTAssertEqual(try error.string("message", at: "native.error"), direct.message)
        guard case .null = error["cause"] else { return XCTFail("Native immediate nil cause must be retained explicitly") }
        let comparison = try baseline.comparison.checkedObject(at: "comparison")
        let projected = try comparison.value("error", at: "comparison").checkedObject(at: "comparison.error")
        XCTAssertEqual(Set(projected.keys), ["name", "message"])
        XCTAssertEqual(try projected.string("name", at: "comparison.error"), "TypeError")
        XCTAssertEqual(try projected.string("message", at: "comparison.error"), direct.message)
        XCTAssertEqual(baseline.rules, ["native-configuration-error-envelope", "typed-identity-configuration-error-taxonomy"])
        XCTAssertNotNil(try JSONComparison.firstDifference(expected: fakeSuccess, actual: baseline.comparison))

        for expected: JSONValue in [.null, .array([]), .object([.test("outcome", .string("threw")), .test("error", .null)])] {
            let alternate = try observed(row(identityJSON(digest: malformed), expected: expected))
            try same(alternate.native, baseline.native)
            try same(alternate.comparison, baseline.comparison)
            XCTAssertEqual(alternate.rules, baseline.rules)
        }
    }

    func testLoneSurrogateIdentityKeysAndValuesRemainPendingWithoutRepair() throws {
        let examples = [
            #"{"formatVersion":1,"catalogVersion":"v1","resolvedFallbackLocale":"en","localeToSha256":{"\uD800":""# + digest + #""}}"#,
            #"{"formatVersion":1,"catalogVersion":"v1","resolvedFallbackLocale":"en","localeToSha256":{"\uDC00":""# + digest + #""}}"#,
            #"{"formatVersion":1,"catalogVersion":"v1","resolvedFallbackLocale":"en","localeToSha256":{"en":"\uD800"}}"#,
            #"{"formatVersion":1,"catalogVersion":"v1","resolvedFallbackLocale":"en","localeToSha256":{"en":"\uDC00"}}"#
        ]
        for (index, input) in examples.enumerated() {
            for expected: JSONValue in [.null, .object([.test("outcome", .string("returned")), .test("value", .null)])] {
                let id = "guard.lone-surrogate-\(index)"
                switch try ManifestContractQualification.execute(row(input, expected: expected, id: id)) {
                case .pending(let carrier, let native):
                    XCTAssertEqual(carrier.id, id)
                    XCTAssertEqual(carrier.category, "native-valid-unicode-string-carrier")
                    XCTAssertEqual(carrier.evidence, "Input JSON requires a lone UTF-16 surrogate; Swift String and public ExactString have no preserving constructor")
                    XCTAssertNil(native, "No manufactured refusal stands in for an unavailable native carrier")
                case .observed: XCTFail("Lone UTF-16 surrogate ingress must not be repaired into a native String")
                }
            }
        }
        let validKey = examples[0].replacingOccurrences(of: #"\uD800"#, with: #"\uFFFD"#)
        let supported = try observed(row(validKey))
        XCTAssertEqual(try supported.native.checkedObject(at: "replacement").string("outcome", at: "replacement"), "returned", "A real replacement-character property name is a supported exact key")
    }

    func testUnknownOperationsAndInputFieldsFailClosedBeforeSubjectDecoding() throws {
        let unknown = ManifestContractQualification.Row(id: "guard.operation", operation: "inventedOperation",
            input: ["identityInputJSON": .string(identityJSON())], expected: .null)
        XCTAssertThrowsError(try ManifestContractQualification.execute(unknown)) {
            XCTAssertEqual(($0 as? ConformanceError)?.description, "Unregistered manifest operation: inventedOperation")
        }
        for field: ExactString in ["unregistered", "expected", "loadingLimits"] {
            let input: [ExactString: JSONValue] = ["identityInputJSON": .string("{ malformed"), field: .null]
            let guarded = ManifestContractQualification.Row(id: "guard.input", operation: "computeCatalogIdentity", input: input, expected: .null)
            XCTAssertThrowsError(try ManifestContractQualification.execute(guarded)) {
                XCTAssertEqual(($0 as? ConformanceError)?.description, "Unknown manifest input field")
            }
        }
    }
}
