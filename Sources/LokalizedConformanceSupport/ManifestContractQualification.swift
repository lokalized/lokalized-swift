import CryptoKit
import Foundation
import Lokalized

public struct ManifestContractPendingCarrier: Encodable, Sendable {
    public let id: String
    public let category: String
    public let evidence: String
}

public struct ManifestContractAdaptation: Encodable, Sendable {
    public let id: String
    public let rules: [String]
    public let nativeObservationJSON: String
    public let referenceObservationJSON: String
    public let comparisonObservationJSON: String
    public let difference: String?
    public let amendedReferenceObservationJSON: String?
}

public struct ManifestContractReport: Encodable, Sendable {
    public let scope = "native-manifest-validation-identity-planning-v1.1"
    public let behaviorProfileID = "manifest-normalization-v1.1"
    public let behaviorProfileVersion = "1.1.0"
    public let behaviorProfileSHA256 = ManifestNormalizationQualification.profileSHA256
    public let archiveCorrectionIDs: [String]
    public let historicalAgreementIDs: [String]
    public let nativeMappingsRatified = false
    public let status: String
    public let totalCases: Int
    public let eligibleIDs: [String]
    public let eligibleIDsSHA256: String
    public let runtimePassed: [String]
    public let strictNativeEqualIDs: [String]
    public let projectedMatchedIDs: [String]
    public let failed: [ConformanceFailure]
    public let pendingCarriers: [ManifestContractPendingCarrier]
    public let pendingObservations: [ManifestContractPendingObservation]
    public let observations: [ManifestContractAdaptation]
    public let adaptationObservations: [ManifestContractAdaptation]
}

public struct ManifestContractPendingObservation: Encodable, Sendable {
    public let id: String
    public let nativeObservationJSON: String?
    public let referenceObservationJSON: String
    public let reason: String
}

/// A separate development contract. It never promotes IDs in the frozen Java
/// corpus. Expected values are consulted only after a real native operation.
public enum ManifestContractQualification {
    public static let vectorsSHA256 = "6356098bbde353a66886e9552c45efe7ec6353697cf26be2141d3e9f4811d50a"
    public static let allIDsSHA256 = "cd23a022f9bd427824c451892ab0e922fb8809945a0eb55571d9d4eccec7966f"

    public static func run(referenceDirectory: URL) throws -> ManifestContractReport {
        let rows = try load(referenceDirectory: referenceDirectory)
        let amendments = try ManifestNormalizationQualification.archiveCorrections(referenceDirectory: referenceDirectory)
        var historicalAgreement: [String] = []
        var eligible: [String] = [], passed: [String] = []
        var strict: [String] = [], projected: [String] = []
        var failed: [ConformanceFailure] = []
        var pending: [ManifestContractPendingCarrier] = []
        var pendingObservations: [ManifestContractPendingObservation] = []
        var observations: [ManifestContractAdaptation] = []
        var adaptations: [ManifestContractAdaptation] = []
        for row in rows {
            do {
                let result = try execute(row)
                switch result {
                case .pending(let reason, let native):
                    pending.append(reason)
                    pendingObservations.append(.init(id: row.id, nativeObservationJSON: try native.map(text),
                        referenceObservationJSON: try text(row.expected), reason: reason.evidence))
                case .observed(let native, let comparison, let rules):
                    eligible.append(row.id)
                    let expected = amendments[row.id] ?? row.expected
                    if try JSONComparison.firstDifference(expected: row.expected, actual: comparison) == nil { historicalAgreement.append(row.id) }
                    let difference = try JSONComparison.firstDifference(expected: expected, actual: comparison)
                    if let difference {
                        failed.append(.init(id: row.id, detail: difference + "; actual=" + (try text(comparison))))
                    } else {
                        passed.append(row.id)
                        if try JSONComparison.firstDifference(expected: expected, actual: native) == nil { strict.append(row.id) }
                        else { projected.append(row.id) }
                    }
                    let observation = ManifestContractAdaptation(id: row.id, rules: rules,
                        nativeObservationJSON: try text(native), referenceObservationJSON: try text(row.expected),
                        comparisonObservationJSON: try text(comparison), difference: difference,
                        amendedReferenceObservationJSON: try amendments[row.id].map(text))
                    observations.append(observation)
                    if !rules.isEmpty { adaptations.append(observation) }
                }
            } catch {
                failed.append(.init(id: row.id, detail: String(describing: error)))
            }
        }
        eligible.sort(); passed.sort(); strict.sort(); projected.sort(); pending.sort { $0.id < $1.id }
        pendingObservations.sort { $0.id < $1.id }; observations.sort { $0.id < $1.id }; adaptations.sort { $0.id < $1.id }
        return .init(archiveCorrectionIDs: amendments.keys.sorted(), historicalAgreementIDs: historicalAgreement.sorted(),
            status: failed.isEmpty ? "passed" : "failed", totalCases: rows.count,
            eligibleIDs: eligible, eligibleIDsSHA256: digestIDs(eligible), runtimePassed: passed,
            strictNativeEqualIDs: strict, projectedMatchedIDs: projected,
            failed: failed, pendingCarriers: pending, pendingObservations: pendingObservations,
            observations: observations, adaptationObservations: adaptations)
    }

    struct Row {
        let id: String
        let operation: String
        let input: [ExactString: JSONValue]
        let expected: JSONValue
    }
    enum Execution {
        case pending(ManifestContractPendingCarrier, native: JSONValue?)
        case observed(native: JSONValue, comparison: JSONValue, rules: [String])
    }
    private struct Pending: Error {
        let category: String
        let evidence: String
        let native: JSONValue?
        init(category: String, evidence: String, native: JSONValue? = nil) {
            self.category = category; self.evidence = evidence; self.native = native
        }
    }
    private struct Options {
        let source: String
        let limits: JSONValue?
    }

    static func load(referenceDirectory: URL) throws -> [Row] {
        let bytes = try ConformanceRunner.boundedRead(referenceDirectory.appendingPathComponent("manifest-contract-vectors.json"), maximumBytes: 8_388_608)
        guard digest(bytes) == vectorsSHA256 else { throw ConformanceError("Manifest contract archive digest differs") }
        let root = try JSONReader.parse(bytes, limits: ConformanceRunner.corpusLimits).checkedObject(at: "manifestContract", allowed: ["formatVersion", "scope", "jsCommit", "buildIdentity", "cases"])
        guard root["formatVersion"].numberLiteral == "1", try root.string("scope", at: "manifestContract") == "js-manifest-validation-identity-planning",
              try root.string("jsCommit", at: "manifestContract") == "617670da887b0c684e2589882447b6b93297f2f7" else { throw ConformanceError("Manifest contract format/source differs") }
        let identity = try root.value("buildIdentity", at: "manifestContract").checkedObject(at: "manifestContract.buildIdentity", allowed: [
            "cldrVersion", "dataFingerprint", "behavioralVectorsVersion", "localeDataMode", "cardinalityMode", "ianaRegistryDate", "ianaDataFingerprint"
        ])
        let metadata = BuildMetadata.current
        let actualIdentity: [String: String] = ["cldrVersion": metadata.cldrVersion, "dataFingerprint": metadata.dataFingerprint,
            "behavioralVectorsVersion": metadata.behavioralVectorsVersion, "localeDataMode": "pinned", "cardinalityMode": "exact",
            "ianaRegistryDate": metadata.ianaRegistryDate, "ianaDataFingerprint": metadata.ianaDataFingerprint]
        for (field, actual) in actualIdentity where try identity.string(field, at: "manifestContract.buildIdentity") != actual {
            throw ConformanceError("Manifest reference runtime identity differs at " + field)
        }
        guard case .array(let values) = try root.value("cases", at: "manifestContract"), values.count == 499 else { throw ConformanceError("Manifest case inventory differs") }
        var rows: [Row] = [], seen: Set<String> = []
        for value in values {
            let fields = try value.checkedObject(at: "manifestContract.case", allowed: ["id", "operation", "input", "expected"])
            let id = try fields.string("id", at: "manifestContract.case")
            guard id.hasPrefix("m7a."), seen.insert(id).inserted else { throw ConformanceError("Invalid/duplicate manifest ID") }
            let operation = try fields.string("operation", at: id)
            let allowed: Set<String>
            switch operation {
            case "parseStringsManifest": allowed = ["carrier", "documentBase64", "text", "optionsJSON"]
            case "computeCatalogIdentity": allowed = ["identityInputJSON"]
            case "chain", "fetchSet": allowed = ["manifestJSON", "lookupLocale", "optionsJSON"]
            case "validateStringsManifest", "localeConfigurationForManifest", "wholeManifestPlan": allowed = ["manifestJSON", "optionsJSON"]
            case "identityForManifest": allowed = ["manifestJSON"]
            default: throw ConformanceError("Unregistered manifest operation: " + operation)
            }
            let input = try fields.value("input", at: id).checkedObject(at: id + ".input", allowed: allowed)
            let expected = try fields.value("expected", at: id)
            try checkExpected(expected, at: id)
            rows.append(.init(id: id, operation: operation, input: input, expected: expected))
        }
        guard rows.map(\.id) == rows.map(\.id).sorted(), digestIDs(rows.map(\.id)) == allIDsSHA256 else { throw ConformanceError("Manifest exact ID inventory differs") }
        return rows
    }

    private static func checkExpected(_ value: JSONValue, at path: String) throws {
        let fields = try value.checkedObject(at: path + ".expected", allowed: ["outcome", "value", "error"])
        switch try fields.string("outcome", at: path) {
        case "returned":
            guard fields.count == 2, fields["value"] != nil else { throw ConformanceError("Malformed returned manifest observation") }
        case "threw":
            guard fields.count == 2 else { throw ConformanceError("Malformed thrown manifest observation") }
            try checkError(fields.value("error", at: path), at: path + ".error", depth: 0)
        default: throw ConformanceError("Unknown manifest outcome")
        }
    }
    private static func checkError(_ value: JSONValue, at path: String, depth: Int) throws {
        guard depth <= 4 else { throw ConformanceError("Manifest error cause depth exceeded") }
        let fields = try value.checkedObject(at: path, allowed: ["name", "message", "code", "source", "line", "column", "path", "cause"])
        _ = try fields.string("name", at: path); _ = try fields.string("message", at: path)
        if let cause = fields["cause"] { try checkError(cause, at: path + ".cause", depth: depth + 1) }
    }

    static func execute(_ row: Row) throws -> Execution {
        let allowed: Set<ExactString>
        switch row.operation {
        case "parseStringsManifest": allowed = ["carrier", "documentBase64", "text", "optionsJSON"]
        case "computeCatalogIdentity": allowed = ["identityInputJSON"]
        case "chain", "fetchSet": allowed = ["manifestJSON", "lookupLocale", "optionsJSON"]
        case "validateStringsManifest", "localeConfigurationForManifest", "wholeManifestPlan": allowed = ["manifestJSON", "optionsJSON"]
        case "identityForManifest": allowed = ["manifestJSON"]
        default: throw ConformanceError("Unregistered manifest operation: " + row.operation)
        }
        guard row.input.keys.allSatisfy(allowed.contains) else { throw ConformanceError("Unknown manifest input field") }
        do {
            let options = try options(row)
            // Decode typed subject carriers before entering the observed call.
            // A missing Swift carrier is pending, never a manufactured refusal.
            let identity: CatalogIdentityInputV1?
            let semantic: StringsManifestValue?
            let typed: StringsManifestV1?
            let lookup: String?
            if row.operation == "computeCatalogIdentity" {
                identity = try typedIdentity(subject(row.input.string("identityInputJSON", at: row.id)))
            } else { identity = nil }
            if row.operation == "validateStringsManifest" {
                semantic = try semanticValue(subject(row.input.string("manifestJSON", at: row.id)))
            } else { semantic = nil }
            if ["identityForManifest", "chain", "fetchSet", "wholeManifestPlan", "localeConfigurationForManifest"].contains(row.operation) {
                typed = try typedManifest(subject(row.input.string("manifestJSON", at: row.id)))
            } else { typed = nil }
            if row.operation == "chain" || row.operation == "fetchSet" {
                guard case .string(let value) = row.input["lookupLocale"] else { throw Pending(category: "typed-lookup-string", evidence: "Native planning lookupLocale is a nonoptional Swift String; this input supplies another JSON value") }
                lookup = value
            } else { lookup = nil }
            do {
                let limits = try CatalogObservations.loadingOptions(options.limits)
                let value: JSONValue
                switch row.operation {
                case "parseStringsManifest":
                    let carrier = try row.input.string("carrier", at: row.id)
                    switch carrier {
                    case "bytes":
                        guard row.input["text"] == nil, let bytes = Data(base64Encoded: try row.input.string("documentBase64", at: row.id)) else { throw ConformanceError("Invalid manifest byte carrier") }
                        value = manifestObservation(try LocalizedStringLoader.parseStringsManifest(bytes, source: options.source, loadingOptions: limits))
                    case "text":
                        guard row.input["documentBase64"] == nil else { throw ConformanceError("Ambiguous manifest text carrier") }
                        value = manifestObservation(try LocalizedStringLoader.parseStringsManifest(row.input.string("text", at: row.id), source: options.source, loadingOptions: limits))
                    default: throw ConformanceError("Unknown manifest raw carrier")
                    }
                case "validateStringsManifest": value = manifestObservation(try LocalizedStringLoader.validateStringsManifest(semantic!, loadingOptions: limits))
                case "computeCatalogIdentity": value = try identityObservation(identity!)
                case "identityForManifest":
                    let input = LocalizedStringLoader.catalogIdentityInputFor(typed!)
                    value = try identityObservation(input, projectedInput: inputObservation(input))
                case "localeConfigurationForManifest":
                    value = configurationObservation(try LocalizedStringLoader.localeConfigurationForManifest(typed!, loadingOptions: limits))
                case "chain": value = .array(try LocalizedStringLoader.chain(typed!, lookupLocale: lookup!, loadingOptions: limits).map(JSONValue.string))
                case "fetchSet": value = .array(try LocalizedStringLoader.fetchSet(typed!, lookupLocale: lookup!, loadingOptions: limits).map(entryObservation))
                case "wholeManifestPlan": value = .array(try LocalizedStringLoader.wholeManifestPlan(typed!, loadingOptions: limits).map(entryObservation))
                default: throw ConformanceError("Unknown manifest operation")
                }
                let observation = JSONValue.object([.test("outcome", .string("returned")), .test("value", value)])
                return .observed(native: observation, comparison: observation, rules: [])
            } catch let error as Pending { throw error }
            catch let error as ConformanceError { throw error }
            catch {
                return try errorExecution(error, row: row, identity: identity)
            }
        } catch let error as Pending {
            return .pending(.init(id: row.id, category: error.category, evidence: error.evidence), native: error.native)
        }
    }

    private static func subject(_ text: String) throws -> JSONValue {
        do { return try JSONReader.parse(text, limits: ConformanceRunner.corpusLimits) }
        catch let error as JSONReadError where error.reason.hasPrefix("Unpaired ") {
            throw Pending(category: "native-valid-unicode-string-carrier", evidence: "Input JSON requires a lone UTF-16 surrogate; Swift String and public ExactString have no preserving constructor")
        }
    }
    private static func options(_ row: Row) throws -> Options {
        guard let value = row.input["optionsJSON"] else { return .init(source: "<manifest>", limits: nil) }
        guard case .string(let text) = value else { throw ConformanceError("optionsJSON must be a string") }
        let decoded = try subject(text)
        let fields = try decoded.checkedObject(at: row.id + ".options")
        let names: Set<ExactString> = row.operation == "parseStringsManifest" ? ["limits", "source"] : ["limits"]
        if fields.keys.contains(where: { !names.contains($0) }) {
            throw Pending(category: "typed-options-no-dynamic-members", evidence: "Input supplies an unknown dynamic JS option; native argument labels cannot express that member")
        }
        let source = try fields["source"].map { value -> String in
            guard case .string(let text) = value else { throw Pending(category: "typed-source-string", evidence: "Native source labels require Swift String") }; return text
        } ?? "<manifest>"
        if let limits = fields["limits"] {
            let budgets = try limits.checkedObject(at: row.id + ".limits")
            let known: Set<ExactString> = ["maximumInputBytes", "maximumReaderCharacters", "maximumJsonNestingDepth", "maximumTotalInputBytes", "maximumLocalizedStringsFiles", "maximumTranslationNodes", "maximumWarnings"]
            if budgets.keys.contains(where: { !known.contains($0) }) { throw Pending(category: "typed-limits-no-dynamic-members", evidence: "Native loading-option value type cannot express an unknown JS budget name") }
            for value in budgets.values {
                guard case .number(let text) = value, Int(text) != nil else { throw Pending(category: "typed-loading-budget-integer", evidence: "Native loading budgets use Int; this input is not an integral native value") }
            }
        }
        return .init(source: source, limits: fields["limits"])
    }
    static func semanticValue(_ value: JSONValue) throws -> StringsManifestValue {
        switch value {
        case .object(let members): return .object(try members.map { .init(name: $0.name, value: try semanticValue($0.value)) })
        case .array(let values): return .array(try values.map(semanticValue))
        case .string(let value): return .string(value)
        case .number(let value): return .number(Double(value) ?? .nan)
        case .bool(let value): return .bool(value)
        case .null: return .null
        }
    }
    private static func typedIdentity(_ value: JSONValue) throws -> CatalogIdentityInputV1 {
        guard case .object = value else { throw Pending(category: "typed-identity-object", evidence: "Native identity API requires a CatalogIdentityInputV1 value, not an arbitrary JSON root") }
        let fields = try value.checkedObject(at: "identityInput")
        let known: Set<ExactString> = ["formatVersion", "catalogVersion", "resolvedFallbackLocale", "localeToSha256", "tiebreakerLocalesByLanguageCode"]
        if fields.keys.contains(where: { !known.contains($0) }) { throw Pending(category: "typed-identity-extra-members", evidence: "Native identity input has exactly five declared fields; this dynamic object supplies another member") }
        guard case .number(let format) = fields["formatVersion"], let version = Int(format),
              case .string(let catalogVersion) = fields["catalogVersion"], case .string(let fallback) = fields["resolvedFallbackLocale"] else {
            throw Pending(category: "typed-identity-required-fields", evidence: "Native required identity fields are Int and nonoptional String; this input omits or mistypes one")
        }
        var digests: [ExactString: String] = [:], ties: [ExactString: [String]] = [:]
        if let value = fields["localeToSha256"], case .null = value {} else if let value = fields["localeToSha256"] {
            let entries = try value.checkedObject(at: "identityInput.localeToSha256")
            for (name, value) in entries {
                guard case .string(let digest) = value else { throw Pending(category: "typed-identity-digest-string", evidence: "Native digest map has nonoptional String values") }; digests[name] = digest
            }
        }
        if let value = fields["tiebreakerLocalesByLanguageCode"], case .null = value {} else if let value = fields["tiebreakerLocalesByLanguageCode"] {
            ties = try typedTies(value)
        }
        return .init(formatVersion: version, catalogVersion: catalogVersion, resolvedFallbackLocale: fallback,
            localeToSha256: digests, tiebreakerLocalesByLanguageCode: ties)
    }
    private static func typedTies(_ value: JSONValue) throws -> [ExactString: [String]] {
        let entries = try value.checkedObject(at: "typedTies")
        var result: [ExactString: [String]] = [:]
        for (name, value) in entries {
            guard case .array(let values) = value else { throw Pending(category: "typed-tiebreaker-string-array", evidence: "Native identity/manifest tiebreaker map requires arrays of Swift String") }
            result[name] = try values.map { value in
                guard case .string(let text) = value else { throw Pending(category: "typed-tiebreaker-string-array", evidence: "Native tiebreaker array elements require Swift String") }; return text
            }
        }
        return result
    }
    private static func typedManifest(_ value: JSONValue) throws -> StringsManifestV1 {
        let fields = try value.checkedObject(at: "typedManifest")
        func string(_ name: String) throws -> String {
            guard case .string(let value) = fields[ExactString(name)] else { throw Pending(category: "typed-manifest-required-fields", evidence: "Planning/claim projection requires typed manifest String fields") }; return value
        }
        guard case .number(let format) = fields["formatVersion"], let version = Int(format) else { throw Pending(category: "typed-manifest-format-integer", evidence: "Typed manifest formatVersion is Int") }
        var files: [ExactString: StringsManifestFile] = [:]
        for (name, value) in try fields.value("files", at: "typedManifest").checkedObject(at: "typedManifest.files") {
            let entry = try value.checkedObject(at: "typedManifest.file")
            guard case .string(let url) = entry["url"], case .string(let digest) = entry["sha256"] else { throw Pending(category: "typed-manifest-file-fields", evidence: "Native manifest file entries require URL/digest String values") }
            let bytes: Int?
            if let value = entry["decodedBytes"] {
                guard case .number(let literal) = value, let count = Int(literal) else { throw Pending(category: "typed-manifest-file-count", evidence: "Native typed manifest decodedBytes is optional Int") }; bytes = count
            } else { bytes = nil }
            files[name] = .init(url: url, sha256: digest, decodedBytes: bytes)
        }
        return try .init(formatVersion: version, catalogVersion: string("catalogVersion"), catalogFingerprint: string("catalogFingerprint"),
            cldrVersion: string("cldrVersion"), dataFingerprint: string("dataFingerprint"), behavioralVectorsVersion: string("behavioralVectorsVersion"),
            localeDataMode: string("localeDataMode"), cardinalityMode: string("cardinalityMode"), ianaRegistryDate: string("ianaRegistryDate"),
            ianaDataFingerprint: string("ianaDataFingerprint"), fallbackLocale: string("fallbackLocale"), baseUrl: string("baseUrl"),
            files: files, tiebreakerLocalesByLanguageCode: typedTies(fields.value("tiebreakerLocalesByLanguageCode", at: "typedManifest")))
    }

    private static func errorExecution(_ error: any Error, row: Row, identity: CatalogIdentityInputV1?) throws -> Execution {
        var native: [JSONMember], compared: [JSONMember], rules: [String] = []
        switch error {
        case let error as ConfigurationError:
            guard error.kind == .invalidArgument else { throw ConformanceError("Unexpected native manifest configuration kind") }
            native = [.test("name", .string("ConfigurationError")), .test("message", .string(error.message)), .test("kind", .string(error.kind.rawValue)), .test("cause", .null)]
            if let cause = error.cause {
                guard let cause = cause as? ManifestURL.Failure, cause.kind == .unsupportedFeature,
                      let feature = cause.feature, try inputURLFeature(row) == feature else { throw ConformanceError("Unregistered native manifest configuration cause") }
                native[native.count - 1] = .test("cause", .object([.test("name", .string("ManifestURL.Failure")),
                    .test("kind", .string("unsupportedFeature")), .test("feature", .string(feature.rawValue)), .test("message", .string(cause.description))]))
                throw Pending(category: "native-url-" + feature.rawValue, evidence: "Actual input URL requires unqualified pinned UTS46/IDNA processing, and the native validator reached that capability refusal",
                    native: .object([.test("outcome", .string("threw")), .test("error", .object(native))]))
            }
            rules.append("native-configuration-error-envelope")
            let projectedName: String
            if row.operation == "computeCatalogIdentity" {
                projectedName = identity!.formatVersion == 1 ? "TypeError" : "RangeError"
                rules.append("typed-identity-configuration-error-taxonomy")
                compared = [.test("name", .string(projectedName)), .test("message", .string(error.message))]
            } else {
                compared = [.test("name", .string("ConfigurationError")), .test("message", .string(error.message)), .test("code", .string("CONFIGURATION"))]
            }
        case let error as LocalizedStringLoadingOptions.ValidationError:
            native = [.test("name", .string("LocalizedStringLoadingOptions.ValidationError")), .test("message", .string(String(describing: error))),
                .test("field", .string(error.field)), .test("value", .number(String(error.value)))]
            compared = [.test("name", .string("RangeError")), .test("message", .string(String(describing: error)))]
            rules.append("typed-loading-options-validation-error-taxonomy")
        case let error as LocaleTagError:
            guard ["chain", "fetchSet"].contains(row.operation), error.kind == .malformedLanguageTag else { throw ConformanceError("Unregistered native manifest locale refusal") }
            native = [.test("name", .string("LocaleTagError")), .test("message", .string(error.message)), .test("kind", .string(error.kind.rawValue))]
            compared = [.test("name", .string("RangeError")), .test("message", .string(error.message))]
            rules.append("native-planning-locale-error-taxonomy")
        case let error as StringsParseError:
            native = [.test("name", .string("StringsParseError")), .test("message", .string(error.message)), .test("source", .string(error.source)),
                .test("line", error.line.map { .number(String($0)) } ?? .null), .test("column", error.column.map { .number(String($0)) } ?? .null),
                .test("path", error.path.map(JSONValue.string) ?? .null), .test("cause", .null)]
            if let cause = error.cause { native[native.count - 1] = .test("cause", try nativeCause(cause)) }
            rules.append("native-strings-parse-error-envelope")
            let prefix = error.source + ": "
            let unlocated = error.line == nil && error.column == nil && error.path == nil
            let sourceFailure = error.message.hasPrefix(prefix + "localized strings resource ")
                || error.message.hasPrefix(prefix + "JSON nesting depth exceeds ")
                || error.message.hasPrefix(prefix + "a localized strings file may not be blank;")
            if unlocated && sourceFailure {
                compared = [.test("name", .string("Error")), .test("message", .string(error.message))]
                rules.append("manifest-preparser-source-error-taxonomy")
            } else {
                compared = [.test("name", .string("StringsParseError")), .test("message", .string(error.message)), .test("code", .string("STRINGS_PARSE")),
                    .test("source", .string(error.source)), .test("line", error.line.map { .number(String($0)) } ?? .null),
                    .test("column", error.column.map { .number(String($0)) } ?? .null), .test("path", error.path.map(JSONValue.string) ?? .null)]
                if let cause = error.cause {
                    guard let cause = cause as? JSONReadError, let line = error.line, let column = error.column,
                          line == cause.location.line, column == cause.location.column else { throw ConformanceError("Unregistered manifest parse cause") }
                    compared.append(.test("cause", .object([.test("name", .string("Error")), .test("message", .string(error.message)),
                        .test("line", .number(String(line))), .test("column", .number(String(column)))])))
                    rules.append("native-json-reader-cause-projection")
                }
            }
        default: throw ConformanceError("Unregistered native manifest error: \(error)")
        }
        return .observed(native: .object([.test("outcome", .string("threw")), .test("error", .object(native))]),
            comparison: .object([.test("outcome", .string("threw")), .test("error", .object(compared))]), rules: rules)
    }
    private static func inputURLFeature(_ row: Row) throws -> ManifestURL.UnqualifiedFeature? {
        let value: JSONValue
        if let argument = row.input["manifestJSON"], case .string(let text) = argument { value = try subject(text) }
        else if row.operation == "parseStringsManifest" {
            if try row.input.string("carrier", at: row.id) == "text" { value = try subject(row.input.string("text", at: row.id)) }
            else {
                guard let bytes = Data(base64Encoded: try row.input.string("documentBase64", at: row.id)) else { throw ConformanceError("Invalid manifest bytes for capability classification") }
                value = try JSONReader.parse(bytes, limits: ConformanceRunner.corpusLimits)
            }
        } else { return nil }
        guard case .object(let members) = value else { return nil }
        let fields = Dictionary(members.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
        guard case .string(let base) = fields["baseUrl"] else { return nil }
        if let feature = ManifestURL.unqualifiedFeature(reference: base) { return feature }
        if case .object(let files) = fields["files"] {
            for file in files {
                guard case .object(let members) = file.value else { continue }
                if let value = members.last(where: { $0.name == "url" })?.value, case .string(let url) = value,
                   let feature = ManifestURL.unqualifiedFeature(reference: url, relativeTo: base) { return feature }
            }
        }
        return nil
    }
    private static func nativeCause(_ error: any Error) throws -> JSONValue {
        guard let error = error as? JSONReadError else { throw ConformanceError("Unregistered native manifest cause") }
        return .object([.test("name", .string("JSONReadError")), .test("reason", .string(error.reason)),
            .test("offset", .number(String(error.location.offset))), .test("line", .number(String(error.location.line))), .test("column", .number(String(error.location.column)))])
    }
    static func manifestObservation(_ value: StringsManifestV1) -> JSONValue {
        let files = value.files.keys.sorted().map { key -> JSONMember in
            let file = value.files[key]!
            var entry: [JSONMember] = [.test("url", .string(file.url)), .test("sha256", .string(file.sha256))]
            if let bytes = file.decodedBytes { entry.append(.test("decodedBytes", .number(String(bytes)))) }
            return .test(key.string, .object(entry))
        }
        return .object([.test("formatVersion", .number(String(value.formatVersion))), .test("catalogVersion", .string(value.catalogVersion)),
            .test("catalogFingerprint", .string(value.catalogFingerprint)), .test("cldrVersion", .string(value.cldrVersion)), .test("dataFingerprint", .string(value.dataFingerprint)),
            .test("behavioralVectorsVersion", .string(value.behavioralVectorsVersion)), .test("localeDataMode", .string(value.localeDataMode)), .test("cardinalityMode", .string(value.cardinalityMode)),
            .test("ianaRegistryDate", .string(value.ianaRegistryDate)), .test("ianaDataFingerprint", .string(value.ianaDataFingerprint)), .test("fallbackLocale", .string(value.fallbackLocale)),
            .test("baseUrl", .string(value.baseUrl)), .test("files", .object(files)), .test("tiebreakerLocalesByLanguageCode", tiesObservation(value.tiebreakerLocalesByLanguageCode))])
    }
    private static func tiesObservation(_ ties: [ExactString: [String]]) -> JSONValue {
        .object(ties.keys.sorted().map { .test($0.string, .array(ties[$0]!.map(JSONValue.string))) })
    }
    private static func inputObservation(_ input: CatalogIdentityInputV1) -> JSONValue {
        .object([.test("formatVersion", .number(String(input.formatVersion))), .test("catalogVersion", .string(input.catalogVersion)),
            .test("resolvedFallbackLocale", .string(input.resolvedFallbackLocale)), .test("localeToSha256", .object(input.localeToSha256.keys.sorted().map { .test($0.string, .string(input.localeToSha256[$0]!)) })),
            .test("tiebreakerLocalesByLanguageCode", tiesObservation(input.tiebreakerLocalesByLanguageCode))])
    }
    static func identityObservation(_ input: CatalogIdentityInputV1, projectedInput: JSONValue? = nil) throws -> JSONValue {
        let bytes = try LocalizedStringLoader.catalogIdentityBytes(input)
        let identity = try LocalizedStringLoader.computeCatalogIdentity(input)
        var fields: [JSONMember] = [.test("identity", .object([.test("catalogVersion", .string(identity.catalogVersion)), .test("catalogFingerprint", .string(identity.catalogFingerprint))])),
            .test("projection", try JSONReader.parse(bytes, limits: ConformanceRunner.corpusLimits)), .test("canonicalBytesBase64", .string(bytes.base64EncodedString())),
            .test("byteCount", .number(String(bytes.count))), .test("sha256", .string(digest(bytes)))]
        if let projectedInput { fields.append(.test("input", projectedInput)) }
        return .object(fields)
    }
    static func configurationObservation(_ value: ManifestLocaleConfiguration) -> JSONValue {
        .object([.test("fallbackLocale", .string(value.fallbackLocale)), .test("supportedLocales", .array(value.supportedLocales.map(JSONValue.string))),
            .test("tiebreakerLocalesByLanguageCode", tiesObservation(Dictionary(uniqueKeysWithValues: value.tiebreakerLocalesByLanguageCode.map { (ExactString($0.key), $0.value) })))])
    }
    static func entryObservation(_ value: FetchEntry) -> JSONValue {
        var fields: [JSONMember] = [.test("locale", .string(value.locale)), .test("url", .string(value.url)), .test("sha256", .string(value.sha256))]
        if let bytes = value.expectedDecodedBytes { fields.append(.test("expectedDecodedBytes", .number(String(bytes)))) }
        return .object(fields)
    }
    private static func text(_ value: JSONValue) throws -> String { String(decoding: try FixtureJSONWriter.bytes(value), as: UTF8.self) }
    private static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private static func digestIDs(_ ids: [String]) -> String { digest(Data(ids.map { $0 + "\n" }.joined().utf8)) }
}
