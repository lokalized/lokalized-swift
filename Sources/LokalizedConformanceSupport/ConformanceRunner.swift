import CryptoKit
import Foundation
import Lokalized

public struct ConformanceError: Error, CustomStringConvertible, Sendable {
    public let description: String
    init(_ description: String) { self.description = description }
}

public struct ConformanceInventory: Encodable, Sendable {
    public let status = "inventory"
    public let corpusVersion: String
    public let totalCases: Int
    public let fixtures: Int
    public let requiredPortable: Int
    public let requiredImplementation: Int
    public let informational: Int
    public let operations: [String: Int]
}

public struct ConformanceFailure: Encodable, Sendable {
    public let id: String
    public let detail: String
}

public struct ConformanceReport: Encodable, Sendable {
    public let status: String
    public let corpusVersion: String
    public let totalCases: Int
    public let requiredPortable: Int
    public let runtimePassed: [String]
    public let nativeRepresentationMapped: [String]
    public let failed: [String]
    public let unimplemented: [String]
    public let failures: [ConformanceFailure]
}

struct BehavioralCase {
    let id: String
    let operation: String
    let partition: String
    let input: JSONValue
    let expected: JSONValue
    let fixture: JSONValue?
    let materializedFiles: [ExactString: Data]?
    let fixtureID: String?

    init(id: String, operation: String, partition: String, input: JSONValue, expected: JSONValue,
         fixture: JSONValue? = nil, materializedFiles: [ExactString: Data]? = nil, fixtureID: String? = nil) {
        self.id = id
        self.operation = operation
        self.partition = partition
        self.input = input
        self.expected = expected
        self.fixture = fixture
        self.materializedFiles = materializedFiles
        self.fixtureID = fixtureID
    }
}

struct BehavioralCorpus {
    let version: String
    let cases: [BehavioralCase]
    let fixtures: Int

    static let operations: Set<String> = [
        "getResult", "get", "matchFor", "languageForms", "load", "parse",
        "loadClasspath", "loadClasspathResources", "construct", "acceptLanguage", "define",
        "cardinalityForNumber", "cardinalityForOperands", "cardinalityForRange",
        "ordinalityForNumber", "ordinalityForOperands",
        "supportedCardinalitiesForLocale", "supportedOrdinalitiesForLocale"
    ]

    init(value: JSONValue, materializedFixtures: [ExactString: [ExactString: Data]]? = nil) throws {
        let root = try value.checkedObject(at: "$", allowed: ["formatVersion", "behavioralVectorsVersion", "oracle", "fixtures", "cases"])
        try root.requireKeys(["formatVersion", "behavioralVectorsVersion", "oracle", "fixtures", "cases"], at: "$")
        guard case .number("1") = root["formatVersion"] else { throw ConformanceError("Unsupported corpus formatVersion") }
        version = try root.string("behavioralVectorsVersion", at: "$")
        let oracle = try root.value("oracle", at: "$").checkedObject(at: "$.oracle", allowed: ["implementation", "javaVersion", "librarySourcesSha256"])
        try oracle.requireKeys(["implementation", "javaVersion", "librarySourcesSha256"], at: "$.oracle")
        for key in ["implementation", "javaVersion", "librarySourcesSha256"] { _ = try oracle.string(key, at: "$.oracle") }
        let fixtureObjects = try root.value("fixtures", at: "$").checkedObject(at: "$.fixtures")
        guard !fixtureObjects.isEmpty else { throw ConformanceError("Corpus contains no fixtures") }
        let fixtureKeys: Set<String> = [
            "bidiIsolation", "constructionOverrides", "description", "entries", "fallbackLocale", "files",
            "instanceLocale", "loadOnly", "loadingOptions", "localeMatchSupplier", "localeSupplier",
            "pathShape", "phoneticResolver", "rawFiles", "rawFilesBase64", "refusesConstruction",
            "runtimeLimits", "tiebreakers", "translationFailureHandler", "translationFallbackPolicy"
        ]
        for (name, fixture) in fixtureObjects {
            let fields = try fixture.checkedObject(at: "$.fixtures.\(name)", allowed: fixtureKeys)
            try fields.requireKeys(fixtureKeys, at: "$.fixtures.\(name)")
        }
        fixtures = fixtureObjects.count
        if let materializedFixtures, Set(materializedFixtures.keys) != Set(fixtureObjects.keys) {
            throw ConformanceError("Materialized fixture inventory differs from corpus fixture IDs")
        }
        guard case .array(let rows) = try root.value("cases", at: "$"), !rows.isEmpty else {
            throw ConformanceError("Corpus cases must be a nonempty array")
        }
        var decoded: [BehavioralCase] = []
        var seen = Set<ExactString>()
        let allowed: Set<String> = ["id", "operation", "partition", "fixture", "input", "expected", "requirementIds", "implementationFamily", "notes", "seedRow", "xfail"]
        let expectedKeys: Set<String> = ["result", "match", "resolverCalls", "supplierCalls", "policyCalls", "construct", "acceptLanguage", "define", "load", "parse", "translation", "failures", "classification", "classifications", "tuples", "thrown"]
        for (index, row) in rows.enumerated() {
            let path = "$.cases[\(index)]"
            let fields = try row.checkedObject(at: path, allowed: allowed)
            try fields.requireKeys(["id", "operation", "partition", "fixture", "input", "expected", "requirementIds"], at: path)
            let id = try fields.string("id", at: path)
            guard Self.validID(id), seen.insert(ExactString(id)).inserted else { throw ConformanceError("Invalid or duplicate case ID: \(id)") }
            let operation = try fields.string("operation", at: path)
            guard Self.operations.contains(operation) else { throw ConformanceError("Unknown corpus operation: \(operation)") }
            let partition = try fields.string("partition", at: path)
            guard ["requiredPortableIds", "requiredImplementationIds", "informationalIds"].contains(partition) else {
                throw ConformanceError("Unknown corpus partition for \(id)")
            }
            if partition == "requiredImplementationIds" {
                guard try !fields.string("implementationFamily", at: path).isEmpty else { throw ConformanceError("Missing implementation family for \(id)") }
            }
            guard fields["xfail"] == nil else { throw ConformanceError("Development xfail is not accepted by the qualification runner: \(id)") }
            let fixture = ExactString(try fields.string("fixture", at: path))
            guard fixtureObjects[fixture] != nil else { throw ConformanceError("Missing fixture for \(id)") }
            let input = try fields.value("input", at: path)
            _ = try input.checkedObject(at: "\(path).input")
            let expected = try fields.value("expected", at: path)
            guard try !expected.checkedObject(at: "\(path).expected", allowed: expectedKeys).isEmpty else {
                throw ConformanceError("Empty expected observation for \(id)")
            }
            guard case .array(let requirements) = try fields.value("requirementIds", at: path) else {
                throw ConformanceError("requirementIds must be an array for \(id)")
            }
            for requirement in requirements {
                guard case .string = requirement else { throw ConformanceError("Invalid requirement ID for \(id)") }
            }
            decoded.append(.init(id: id, operation: operation, partition: partition, input: input, expected: expected,
                                 fixture: fixtureObjects[fixture], materializedFiles: materializedFixtures?[fixture], fixtureID: fixture.string))
        }
        cases = decoded
    }

    private static func validID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard !bytes.isEmpty else { return false }
        var expectsAlphanumeric = true
        for byte in bytes {
            if (97...122).contains(byte) || (48...57).contains(byte) { expectsAlphanumeric = false }
            else if (byte == 45 || byte == 46) && !expectsAlphanumeric { expectsAlphanumeric = true }
            else { return false }
        }
        return !expectsAlphanumeric
    }

    var inventory: ConformanceInventory {
        .init(corpusVersion: version, totalCases: cases.count, fixtures: fixtures,
              requiredPortable: cases.filter { $0.partition == "requiredPortableIds" }.count,
              requiredImplementation: cases.filter { $0.partition == "requiredImplementationIds" }.count,
              informational: cases.filter { $0.partition == "informationalIds" }.count,
              operations: Dictionary(cases.map { ($0.operation, 1) }, uniquingKeysWith: +))
    }
}

public enum ConformanceRunner {
    static let corpusSHA256 = "1eb74caf8524c0a3b33dca99addb268c86b64eb8321fac03257474ddaa3c9753"
    // The frozen corpus itself reaches depth 132 because it embeds catalogs that
    // must later be rejected by the normal loader. This envelope is not a catalog.
    static let corpusLimits = JSONReadingLimits(maximumCharacters: 8_388_608, maximumDepth: 256, maximumNodes: 1_000_000)

    public static func inventory(referenceDirectory: URL) throws -> ConformanceInventory {
        try load(referenceDirectory: referenceDirectory).inventory
    }

    public static func audit(referenceDirectory: URL) throws -> ConformanceReport {
        try audit(load(referenceDirectory: referenceDirectory))
    }

    static func audit(_ corpus: BehavioralCorpus) throws -> ConformanceReport {
        var passed: [String] = []
        var failed: [String] = []
        var unimplemented: [String] = []
        var failures: [ConformanceFailure] = []
        let runtime = RuntimeObservations.Session()
        let loader = LoaderObservations.Session()
        for row in corpus.cases {
            do {
                guard let actual = try execute(row, runtime: runtime, loader: loader) else { unimplemented.append(row.id); continue }
                if let difference = try JSONComparison.firstDifference(expected: row.expected, actual: actual) {
                    failed.append(row.id)
                    failures.append(.init(id: row.id, detail: difference))
                } else { passed.append(row.id) }
            } catch {
                failed.append(row.id)
                failures.append(.init(id: row.id, detail: String(describing: error)))
            }
        }
        // Typed Swift exclusions require a separate compiler-evidence registry.
        // Candidate mappings in Reference/baseline.json are never runtime passes.
        let mapped: [String] = []
        let accounting = passed + mapped + failed + unimplemented
        guard accounting.count == corpus.cases.count,
              Set(accounting.map { ExactString($0) }).count == corpus.cases.count else {
            throw ConformanceError("Nonexhaustive or overlapping disposition lists")
        }
        let required = Set(corpus.cases.filter { $0.partition != "informationalIds" }.map { ExactString($0.id) })
        let requiredFailed = failed.contains { required.contains(ExactString($0)) }
        let requiredPending = unimplemented.contains { required.contains(ExactString($0)) }
        let status = requiredFailed ? "failed" : (requiredPending ? "incomplete" : "passed")
        return .init(status: status, corpusVersion: corpus.version, totalCases: corpus.cases.count,
                     requiredPortable: corpus.inventory.requiredPortable, runtimePassed: passed,
                     nativeRepresentationMapped: mapped, failed: failed, unimplemented: unimplemented, failures: failures)
    }

    static func execute(_ row: BehavioralCase, runtime: RuntimeObservations.Session? = nil,
                        loader: LoaderObservations.Session? = nil) throws -> JSONValue? {
        // No permissive default decoder: a new operation must be deliberately
        // registered, and a known but unfinished operation stays unimplemented.
        guard BehavioralCorpus.operations.contains(row.operation) else { throw ConformanceError("Unknown operation: \(row.operation)") }
        switch row.operation {
        case "languageForms":
            let input = try row.input.checkedObject(at: "$.input", allowed: [])
            guard input.isEmpty else { throw ConformanceError("languageForms takes no inputs") }
            return languageFormsObservation()
        case "parse": return try CatalogObservations.parse(row)
        case "define": return try CatalogObservations.define(row)
        case let operation where PluralObservations.operations.contains(operation): return try PluralObservations.execute(row)
        case "matchFor", "acceptLanguage": return try LocaleObservations.execute(row)
        case "get", "getResult", "construct": return try (runtime ?? RuntimeObservations.Session()).execute(row)
        case "load":
            guard try LoaderObservations.pendingAdaptations(row).isEmpty else { return nil }
            return try (loader ?? LoaderObservations.Session()).execute(row)
        default: return nil
        }
    }

    static func languageFormsObservation() -> JSONValue {
        func tuples<Form: LanguageForm & CaseIterable>(_ type: Form.Type, axis: String) -> [JSONValue] {
            Form.allCases.map { form in
                .object([
                    .test("axis", .string(axis)), .test("name", .string(form.rawValue)),
                    .test("renderName", .string(form.displayName)), .test("rendered", .string(String(describing: form)))
                ])
            }
        }
        let all = tuples(Cardinality.self, axis: "cardinality")
            + tuples(Ordinality.self, axis: "ordinality")
            + tuples(Gender.self, axis: "gender")
            + tuples(GrammaticalCase.self, axis: "grammatical-case")
            + tuples(Definiteness.self, axis: "definiteness")
            + tuples(Classifier.self, axis: "classifier")
            + tuples(Formality.self, axis: "formality")
            + tuples(Clusivity.self, axis: "clusivity")
            + tuples(Animacy.self, axis: "animacy")
            + tuples(Phonetic.self, axis: "phonetic")
        return .object([.test("tuples", .array(all))])
    }

    static func load(referenceDirectory: URL) throws -> BehavioralCorpus {
        let data = try boundedRead(referenceDirectory.appendingPathComponent("behavioral-vectors.json"), maximumBytes: 8_388_608)
        let digest = SHA256.hash(data: data).map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
        guard digest == corpusSHA256 else { throw ConformanceError("Behavioral corpus digest does not match the compiled baseline") }
        let baseline = try JSONReader.parse(boundedRead(referenceDirectory.appendingPathComponent("baseline.json"), maximumBytes: 1_048_576))
        let fields = try baseline.checkedObject(at: "baseline")
        guard fields["formatVersion"].numberLiteral == "1",
              try fields.string("baselineId", at: "baseline") == "java-3.1.0-cldr-48.2-iana-2026-09-17" else {
            throw ConformanceError("Unsupported reference baseline format or identity")
        }
        let manifest = try fields.value("corpus", at: "baseline").checkedObject(at: "baseline.corpus")
        guard try manifest.string("sha256", at: "baseline.corpus") == corpusSHA256,
              manifest["cases"].numberLiteral == "2381", manifest["fixtures"].numberLiteral == "586",
              manifest["requiredPortableIds"].numberLiteral == "2155", manifest["requiredImplementationIds"].numberLiteral == "0",
              manifest["informationalIds"].numberLiteral == "226",
              try manifest.string("behavioralVectorsVersion", at: "baseline.corpus") == BuildMetadata.current.behavioralVectorsVersion else {
            throw ConformanceError("Reference baseline disagrees with the compiled corpus identity")
        }
        let dataFields = try fields.value("data", at: "baseline").checkedObject(at: "baseline.data")
        for (key, expected) in [
            ("cldrVersion", BuildMetadata.current.cldrVersion), ("dataFingerprint", BuildMetadata.current.dataFingerprint),
            ("ianaRegistryDate", BuildMetadata.current.ianaRegistryDate), ("ianaDataFingerprint", BuildMetadata.current.ianaDataFingerprint),
            ("identifierUnicodeVersion", BuildMetadata.current.identifierUnicodeVersion)
        ] {
            guard try dataFields.string(key, at: "baseline.data") == expected else { throw ConformanceError("Reference data pin mismatch: \(key)") }
        }
        let materialized = try MaterializedFixtures.load(referenceDirectory: referenceDirectory)
        let corpus = try BehavioralCorpus(value: JSONReader.parse(data, limits: corpusLimits), materializedFixtures: materialized)
        let inventory = corpus.inventory
        guard inventory.totalCases == 2_381, inventory.fixtures == 586, inventory.requiredPortable == 2_155,
              inventory.requiredImplementation == 0, inventory.informational == 226,
              inventory.corpusVersion == BuildMetadata.current.behavioralVectorsVersion else {
            throw ConformanceError("Corpus coverage inventory disagrees with the compiled baseline")
        }
        return corpus
    }

    static func boundedRead(_ url: URL, maximumBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= maximumBytes {
            let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
        }
        throw ConformanceError("Reference file exceeds byte budget: \(url.lastPathComponent)")
    }
}

extension JSONMember {
    static func test(_ name: String, _ value: JSONValue) -> Self {
        .init(name: ExactString(name), value: value, location: .init(offset: 0, line: 1, column: 1))
    }
}

extension JSONValue {
    func checkedObject(at path: String, allowed: Set<String>? = nil) throws -> [ExactString: JSONValue] {
        guard case .object(let members) = self else { throw ConformanceError("Expected object at \(path)") }
        var result: [ExactString: JSONValue] = [:]
        let allowedExact = allowed.map { Set($0.map { ExactString($0) }) }
        for member in members {
            guard result[member.name] == nil else { throw ConformanceError("Duplicate member \(member.name) at \(path)") }
            if let allowedExact, !allowedExact.contains(member.name) { throw ConformanceError("Unknown field \(member.name) at \(path)") }
            result[member.name] = member.value
        }
        return result
    }
}

extension Optional where Wrapped == JSONValue {
    var numberLiteral: String? {
        guard case .number(let value) = self else { return nil }
        return value
    }
}

extension Dictionary where Key == ExactString, Value == JSONValue {
    func requireKeys(_ names: Set<String>, at path: String) throws {
        for name in names where self[ExactString(name)] == nil { throw ConformanceError("Missing field \(name) at \(path)") }
    }
    func value(_ name: String, at path: String) throws -> JSONValue {
        guard let value = self[ExactString(name)] else { throw ConformanceError("Missing field \(name) at \(path)") }
        return value
    }
    func string(_ name: String, at path: String) throws -> String {
        guard case .string(let value) = try value(name, at: path) else { throw ConformanceError("Expected string at \(path).\(name)") }
        return value
    }
}

enum JSONComparison {
    /// Object order is irrelevant; member spelling, duplicates, all fields and
    /// array order matter. Numeric lexemes compare exactly until the decimal
    /// engine provides an exact numeric observation adapter.
    static func firstDifference(expected: JSONValue, actual: JSONValue, path: String = "$") throws -> String? {
        switch (expected, actual) {
        case (.object, .object):
            let lhs = try expected.checkedObject(at: path)
            let rhs = try actual.checkedObject(at: path)
            guard Set(lhs.keys) == Set(rhs.keys) else { return "Object fields differ at \(path)" }
            for key in lhs.keys.sorted() {
                if let difference = try firstDifference(expected: lhs[key]!, actual: rhs[key]!, path: "\(path).\(key)") { return difference }
            }
            return nil
        case (.array(let lhs), .array(let rhs)):
            guard lhs.count == rhs.count else { return "Array lengths differ at \(path)" }
            for index in lhs.indices {
                if let difference = try firstDifference(expected: lhs[index], actual: rhs[index], path: "\(path)[\(index)]") { return difference }
            }
            return nil
        case (.string(let lhs), .string(let rhs)): return ExactString(lhs) == ExactString(rhs) ? nil : "String code units differ at \(path)"
        case (.number(let lhs), .number(let rhs)): return lhs == rhs ? nil : "Number literals differ at \(path)"
        case (.bool(let lhs), .bool(let rhs)): return lhs == rhs ? nil : "Booleans differ at \(path)"
        case (.null, .null): return nil
        default: return "JSON types differ at \(path)"
        }
    }
}
