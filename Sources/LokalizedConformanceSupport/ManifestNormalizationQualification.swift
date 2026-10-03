import CryptoKit
import Foundation
import Lokalized

public struct ManifestNormalizationReport: Encodable, Sendable {
    public let scope = "manifest-normalization-v1.1"
    public let profileVersion = "1.1.0"
    public let profileSHA256 = ManifestNormalizationQualification.profileSHA256
    public let status: String
    public let totalCases: Int
    public let passedIDs: [String]
    public let failed: [ConformanceFailure]
    public let observations: [ManifestContractAdaptation]
}

public enum ManifestNormalizationQualification {
    public static let profileSHA256 = "9fb02c5a607e6288ef46e49a9161a4bc0d0d23aed98931f7c0482a21a8714162"
    private static func profile(_ reference: URL) throws -> [ExactString: JSONValue] {
        let data = try ConformanceRunner.boundedRead(reference.appendingPathComponent("manifest-normalization-v1.1.json"), maximumBytes: 1_048_576)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == profileSHA256 else {
            throw ConformanceError("Manifest normalization profile digest differs")
        }
        return try JSONReader.parse(data, limits: ConformanceRunner.corpusLimits).checkedObject(at: "normalization")
    }
    static func archiveCorrections(referenceDirectory: URL) throws -> [String: JSONValue] {
        guard case .array(let rows) = try profile(referenceDirectory).value("archiveCorrections", at: "normalization") else { throw ConformanceError("Missing amendments") }
        return try Dictionary(uniqueKeysWithValues: rows.map { value in
            let row = try value.checkedObject(at: "amendment")
            return (try row.string("id", at: "amendment"), try row.value("expected", at: "amendment"))
        })
    }
    public static func run(referenceDirectory: URL) throws -> ManifestNormalizationReport {
        guard case .array(let values) = try profile(referenceDirectory).value("cases", at: "normalization") else { throw ConformanceError("Missing normalization cases") }
        var passed: [String] = [], failed: [ConformanceFailure] = [], observations: [ManifestContractAdaptation] = []
        for value in values {
            let fields = try value.checkedObject(at: "normalization.case")
            let id = try fields.string("id", at: "normalization.case")
            let row = ManifestContractQualification.Row(id: id, operation: try fields.string("operation", at: id),
                input: try fields.value("input", at: id).checkedObject(at: id), expected: try fields.value("expected", at: id))
            do {
                let execution = try execute(row)
                guard case .observed(let native, let comparison, let rules) = execution else { throw ConformanceError("Unexpected pending normalization carrier") }
                let difference = try JSONComparison.firstDifference(expected: row.expected, actual: comparison)
                if let difference { failed.append(.init(id: id, detail: difference + "; actual=" + (try text(comparison)))) }
                else { passed.append(id) }
                observations.append(.init(id: id, rules: rules, nativeObservationJSON: try text(native), referenceObservationJSON: try text(row.expected),
                    comparisonObservationJSON: try text(comparison), difference: difference, amendedReferenceObservationJSON: nil))
            } catch { failed.append(.init(id: id, detail: String(describing: error))) }
        }
        return .init(status: failed.isEmpty ? "passed" : "failed", totalCases: values.count, passedIDs: passed, failed: failed, observations: observations)
    }
    static func execute(_ row: ManifestContractQualification.Row) throws -> ManifestContractQualification.Execution {
        let observed: JSONValue
        switch row.operation {
        case "normalize":
            let tag = try row.input.string("tag", at: row.id)
            let normalized = try ManifestLocale.normalizeTag(tag)
            observed = .object([.test("normalized", .string(normalized)), .test("repeated", .string(try ManifestLocale.normalizeTag(normalized))),
                .test("coreProjection", .string(LocaleTag.forLanguageTag(tag).tag))])
        case "roundTrip":
            let document = try row.input.string("manifestJSON", at: row.id)
            let semantic = try ManifestContractQualification.semanticValue(JSONReader.parse(document, limits: ConformanceRunner.corpusLimits))
            let validated = try LocalizedStringLoader.validateStringsManifest(semantic)
            let parsedText = try LocalizedStringLoader.parseStringsManifest(document)
            let parsedBytes = try LocalizedStringLoader.parseStringsManifest(Data(document.utf8))
            let repeated = try LocalizedStringLoader.validateStringsManifest(LocalizedStringLoader.validateStringsManifest(validated))
            let identity = LocalizedStringLoader.catalogIdentityInputFor(validated)
            let configuration = try LocalizedStringLoader.localeConfigurationForManifest(validated)
            let chain = try LocalizedStringLoader.chain(validated, lookupLocale: "de")
            let fetch = try LocalizedStringLoader.fetchSet(validated, lookupLocale: "de")
            let whole = try LocalizedStringLoader.wholeManifestPlan(validated)
            let authored = try LocalizedStringLoader.fetchSet(validated, lookupLocale: row.input.string("lookupLocale", at: row.id))
            let canonical = try LocalizedStringLoader.fetchSet(validated, lookupLocale: validated.fallbackLocale)
            let input = try JSONReader.parse(LocalizedStringLoader.catalogIdentityBytes(identity), limits: ConformanceRunner.corpusLimits)
            observed = .object([.test("validated", ManifestContractQualification.manifestObservation(validated)),
                .test("parsedText", ManifestContractQualification.manifestObservation(parsedText)),
                .test("parsedBytes", ManifestContractQualification.manifestObservation(parsedBytes)),
                .test("revalidated", ManifestContractQualification.manifestObservation(repeated)),
                .test("configuration", ManifestContractQualification.configurationObservation(configuration)),
                .test("identity", try ManifestContractQualification.identityObservation(identity, projectedInput: input)),
                .test("chain", .array(chain.map(JSONValue.string))), .test("fetchSet", .array(fetch.map(ManifestContractQualification.entryObservation))),
                .test("wholePlan", .array(whole.map(ManifestContractQualification.entryObservation))),
                .test("lookupAuthored", .array(authored.map(ManifestContractQualification.entryObservation))),
                .test("lookupCanonical", .array(canonical.map(ManifestContractQualification.entryObservation)))])
        case "parseStringsManifest":
            var input = row.input
            input["text"] = input.removeValue(forKey: "manifestJSON")
            input["carrier"] = .string("text")
            return try ManifestContractQualification.execute(.init(id: row.id, operation: row.operation, input: input, expected: row.expected))
        default: return try ManifestContractQualification.execute(row)
        }
        let native = JSONValue.object([.test("outcome", .string("returned")), .test("value", observed)])
        return .observed(native: native, comparison: native, rules: [])
    }
    private static func text(_ value: JSONValue) throws -> String { String(decoding: try FixtureJSONWriter.bytes(value), as: UTF8.self) }
}
