import CryptoKit
import Foundation
import Lokalized

public struct LoaderPendingCarrier: Encodable, Sendable {
    public let id: String
    public let category: String
    public let evidence: String
}

public struct LoaderQualificationReport: Encodable, Sendable {
    public let scope = "native-filesystem-full-observation"
    public let status: String
    public let eligibleIDs: [String]
    public let eligibleIDsSHA256: String
    public let runtimePassed: [String]
    public let failed: [ConformanceFailure]
    public let pendingCarriers: [LoaderPendingCarrier]
    public let adaptationObservations: [LoaderAdaptationObservation]
}

public struct LoaderAdaptationObservation: Encodable, Sendable {
    public let id: String
    public let nativeObservationJSON: String
    public let referenceObservationJSON: String
    public let difference: String?
}

/// The frozen `load` operation supplies a directory/path-shaped input. JVM
/// classpath lookup remains an explicit missing carrier rather than a fake URL
/// map pass. All recorded load fields and warning order are compared exactly.
public enum LoaderQualification {
    public static func run(referenceDirectory: URL) throws -> LoaderQualificationReport {
        let corpus = try ConformanceRunner.load(referenceDirectory: referenceDirectory)
        let session = LoaderObservations.Session()
        var eligible: [String] = [], passed: [String] = [], failures: [ConformanceFailure] = []
        var pending: [LoaderPendingCarrier] = []
        var adaptations: [LoaderAdaptationObservation] = []
        for row in corpus.cases {
            switch row.operation {
            case "load":
                let guards = try LoaderObservations.pendingAdaptations(row)
                if !guards.isEmpty {
                    pending.append(contentsOf: guards)
                    let actual = try session.execute(row)
                    adaptations.append(.init(id: row.id, nativeObservationJSON: String(decoding: try FixtureJSONWriter.bytes(actual), as: UTF8.self),
                        referenceObservationJSON: String(decoding: try FixtureJSONWriter.bytes(row.expected), as: UTF8.self),
                        difference: try JSONComparison.firstDifference(expected: row.expected, actual: actual)))
                    continue
                }
                eligible.append(row.id)
                do {
                    let actual = try session.execute(row)
                    if let difference = try JSONComparison.firstDifference(expected: row.expected, actual: actual) {
                        failures.append(.init(id: row.id, detail: difference + "; actual=" + String(decoding: try FixtureJSONWriter.bytes(actual), as: UTF8.self)))
                    } else { passed.append(row.id) }
                } catch { failures.append(.init(id: row.id, detail: String(describing: error))) }
            case "loadClasspath":
                _ = try row.input.checkedObject(at: "loadClasspath.input", allowed: ["package"])
                pending.append(.init(id: row.id, category: "jvm-classpath-discovery",
                    evidence: "Input requests URLClassLoader package discovery; native directory/Bundle URL APIs do not replay JVM package normalization, roots, JAR discovery or classloader lookup"))
            case "loadClasspathResources":
                _ = try row.input.checkedObject(at: "loadClasspathResources.input", allowed: ["resources"])
                pending.append(.init(id: row.id, category: "jvm-classpath-resource-resolution",
                    evidence: "Input maps locales to classloader-relative resource names; native loadFromResources takes already-resolved URLs, so resource-name grammar, root selection and lookup failures are a different carrier"))
            default: break
            }
        }
        eligible.sort(); passed.sort(); pending.sort { $0.id < $1.id }
        let digest = SHA256.hash(data: Data(eligible.map { $0 + "\n" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(status: failures.isEmpty ? "passed" : "failed", eligibleIDs: eligible, eligibleIDsSHA256: digest,
            runtimePassed: passed, failed: failures, pendingCarriers: pending, adaptationObservations: adaptations)
    }

    /// Real filesystem -> public catalog supplier -> public translation, with
    /// separate instances and changed source bytes. No frozen expected fields
    /// configure these probes or serve as lookup tables.
    static func runNative() throws -> Int {
        var checks = 0
        func require(_ value: Bool, _ message: String) throws {
            guard value else { throw ConformanceError("Native loader qualification: " + message) }; checks += 1
        }
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("lokalized-native-loader-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("en.JSON")
        try Data(#"{"Greeting":"first {{name}}","é":"NFC","e\u0301":"NFD"}"#.utf8).write(to: file)
        let loaded = try LocalizedStringLoader.loadFromDirectory(directory)
        let en = LocaleTag.forLanguageTag("en")
        try require(loaded.count == 1 && loaded[en]?.strings.count == 3, "real case-insensitive .json filename load")
        let oldCatalogs = loaded.mapValues { LocalizedCatalog(strings: $0.strings) }
        let old = try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { oldCatalogs }, localeSupplier: { _ in en }, fallbackLocale: en))
        let result = try old.getResult("Greeting", placeholders: ["name": .text("Ada")])
        try require(result.translation == "first Ada" && result.status == .translated && result.resolvedLocale == en, "loaded catalog produces a full public translated result")
        try require(try old.get("é") == "NFC" && old.get(ExactString("e\u{0301}")) == "NFD", "loaded catalog preserves exact canonical-equivalent key identity")
        try Data(#"{"Greeting":"second {{name}}"}"#.utf8).write(to: file)
        let newerCatalogs = try LocalizedStringLoader.loadFromDirectory(directory).mapValues { LocalizedCatalog(strings: $0.strings) }
        let newer = try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { newerCatalogs }, localeSupplier: { _ in en }, fallbackLocale: en))
        try require(try old.get("Greeting", placeholders: ["name": .text("Ada")]) == "first Ada", "first instance retains immutable loaded snapshot after physical source changes")
        try require(try newer.get("Greeting", placeholders: ["name": .text("Ada")]) == "second Ada", "second instance observes new real source bytes independently")
        let resourceMap = try LocalizedStringLoader.loadFromResources([en: file])
        try require(resourceMap[en]?.strings.first?.translation == "second {{name}}", "native explicit URL resource map loads real bytes")
        let projection = FixturePathProjection(root: directory)
        try require(projection.apply(directory.path + "/en:1:2: message") == "<fixtures>/en:1:2: message", "normalization retains suffix and parse position")
        try require(projection.apply("Location '\(directory.path)' failed") == "Location '<fixtures>' failed", "normalization respects quoted complete path")
        try require(projection.apply("file:\(directory.path)/en") == "<fixtures>/en", "normalization projects explicit file URL carrier")
        try require(projection.apply("prefix\(directory.path)/en") == "prefix\(directory.path)/en", "normalization leaves larger text tokens intact")
        try require(projection.apply(directory.path + "-other/en") == directory.path + "-other/en", "normalization leaves neighboring roots intact")
        // Creation order is deliberately reversed. The native contract sorts
        // unsigned UTF-8 filename bytes after bounded enumeration, so this is
        // independent of the directory's physical traversal order.
        try Data("{}".utf8).write(to: directory.appendingPathComponent("zz.json"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("notes.json"))
        do {
            _ = try LocalizedStringLoader.loadFromDirectory(directory)
            throw ConformanceError("Native loader accepted competing invalid locale filenames")
        } catch let error as LocalizedStringLoadingError {
            try require(error.kind == .invalidResource && error.message.hasPrefix("File 'notes.json'"), "deterministic invalid-file priority is unsigned UTF-8 order, independent of creation order")
        }
        return checks
    }
}
