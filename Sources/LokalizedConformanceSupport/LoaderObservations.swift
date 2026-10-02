import Foundation
import Darwin
import Lokalized

/// Executes the public native filesystem loader against actual, owned fixture
/// trees. Classloader/JAR resource semantics are deliberately separate carriers.
enum LoaderObservations {
    /// These guards describe unresolved diagnostic precedence from input shape.
    /// They neither consult expected values nor fabricate an observed refusal.
    static func pendingAdaptations(_ row: BehavioralCase) throws -> [LoaderPendingCarrier] {
        guard row.operation == "load", let fixture = row.fixture else { return [] }
        _ = try row.input.checkedObject(at: "load.input", allowed: [])
        let fields = try fixture.checkedObject(at: "load.fixture")
        guard case .string("directory") = fields["pathShape"] else { return [] }
        let options: LocalizedStringLoadingOptions
        do { options = try CatalogObservations.loadingOptions(fields["loadingOptions"]) }
        catch is LocalizedStringLoadingOptions.ValidationError { return [] }
        var names = Set<ExactString>()
        for name in ["files", "rawFiles", "rawFilesBase64"] {
            names.formUnion(try fields.value(name, at: "load.fixture").checkedObject(at: name).keys)
        }
        var invalidJSON: [String] = [], valid: [(name: String, stem: String, json: Bool, locale: LocaleTag)] = []
        for name in names.sorted() {
            let bytes = Array(name.string.utf8)
            guard bytes.first != 46, !bytes.contains(47) else { continue }
            let hasJSON = bytes.count >= 5 && bytes.suffix(5).map { (65...90).contains($0) ? $0 + 32 : $0 } == Array(".json".utf8)
            let stem = hasJSON ? String(decoding: bytes.dropLast(5), as: UTF8.self) : name.string
            if JDKLocaleTag.isCatalogLanguageTag(stem) {
                valid.append((name.string, stem, hasJSON, LocaleTag.forLanguageTag(stem)))
            } else if hasJSON { invalidJSON.append(name.string) }
        }
        var pending: [LoaderPendingCarrier] = []
        if invalidJSON.count > 1 {
            pending.append(.init(id: row.id, category: "native-competing-invalid-json-filenames",
                evidence: "Multiple regular .json filenames have invalid locale stems: \(invalidJSON.map(FixtureJSONWriter.quote).joined(separator: ", ")). Native bounded discovery sorts unsigned UTF-8 filename bytes; frozen Java raw directory traversal selected a different first diagnostic"))
        }
        if Set(valid.map(\.locale)).count > options.maximumLocalizedStringsFiles {
            pending.append(.init(id: row.id, category: "native-aggregate-file-cap-diagnostic-order",
                evidence: "Input contains \(Set(valid.map(\.locale)).count) distinct loadable locale files and a cap of \(options.maximumLocalizedStringsFiles). Native unsigned UTF-8 ordering determines the file naming the cap overflow; this diagnostic precedence remains unresolved against frozen raw directory traversal"))
        }
        let alternateNames = valid.filter { candidate in
            candidate.json && valid.contains { !$0.json && ExactString($0.name) == ExactString(candidate.stem) && $0.locale == candidate.locale }
        }.map(\.name)
        if !alternateNames.isEmpty {
            pending.append(.init(id: row.id, category: "native-extensionless-json-alias-diagnostic-order",
                evidence: "The same exact locale basename has both extensionless and ASCII case-insensitive .json filenames: \(alternateNames.map(FixtureJSONWriter.quote).joined(separator: ", ")). Native sorted processing reports the later .json spelling; this is a specific alternate-filename diagnostic precedence guard, not a blanket duplicate-locale mapping"))
        }
        return pending
    }

    final class Session {
        private var materializer: FixtureMaterializer?

        func load(_ row: BehavioralCase, warningHandler: LocalizedStringWarningHandler? = nil) throws -> [LocaleTag: ParsedStringsFile] {
            guard let fixture = row.fixture else { throw ConformanceError("Load operation has no fixture") }
            let fields = try fixture.checkedObject(at: "load.fixture")
            if materializer == nil { materializer = try FixtureMaterializer() }
            let location = try materializer!.directory(row)
            return try LocalizedStringLoader.loadFromDirectory(location, warningHandler: warningHandler,
                loadingOptions: CatalogObservations.loadingOptions(fields["loadingOptions"]))
        }

        func execute(_ row: BehavioralCase) throws -> JSONValue {
            guard row.operation == "load", row.fixture != nil else { throw ConformanceError("Unregistered or fixtureless filesystem load") }
            _ = try row.input.checkedObject(at: "load.input", allowed: [])
            // Fixture authoring/materialization failures cannot impersonate a
            // source-loader refusal. Materialize before the observed operation.
            if materializer == nil { materializer = try FixtureMaterializer() }
            _ = try materializer!.directory(row)
            let recorder = LoadWarningRecorder()
            var observed: [JSONMember]
            do {
                let result = try load(row, warningHandler: { recorder.append($0) })
                let pairs = result.keys.sorted { ExactString($0.tag) < ExactString($1.tag) }.map { locale in
                    JSONMember.test(locale.tag, .array(result[locale]!.strings.map(\.key).sorted().map { .string($0.string) }))
                }
                observed = [.test("locales", .array(pairs.map { .string($0.name.string) })), .test("keysByLocale", .object(pairs)),
                    .test("failed", .bool(false)), .test("failureType", .null), .test("failureMessage", .null)]
            } catch {
                if error is ConformanceError { throw error }
                let projected = try errorProjection(error)
                observed = [.test("locales", .array([])), .test("keysByLocale", .object([])), .test("failed", .bool(true)),
                    .test("failureType", .string(projected.type)), .test("failureMessage", .string(materializer!.project(projected.message)))]
            }
            let warningValues: [JSONValue] = recorder.snapshot.map { warning in
                let missing: [JSONValue] = warning.missingLanguageForms.map { ExactString($0) }.sorted().map { .string($0.string) }
                let members: [JSONMember] = [.test("key", warning.key.map { .string($0.string) } ?? .null), .test("locale", warning.locale.map(JSONValue.string) ?? .null),
                    .test("message", .string(materializer!.project(warning.message))),
                    .test("missingLanguageForms", .array(missing)),
                    .test("placeholder", warning.placeholder.map { .string($0.string) } ?? .null),
                    .test("source", .string(materializer!.project(warning.source))), .test("type", .string(warning.type.rawValue))]
                return .object(members)
            }
            observed.append(.test("warnings", .array(warningValues)))
            return .object([.test("load", .object(observed))])
        }
    }

    private static func errorProjection(_ error: any Error) throws -> (type: String, message: String) {
        switch error {
        case let error as StringsParseError: ("com.lokalized.LocalizedStringLoadingException", error.message)
        case let error as LocalizedStringLoadingError: ("com.lokalized.LocalizedStringLoadingException", error.message)
        case let error as LocalizedStringLoadingOptions.ValidationError: ("java.lang.IllegalArgumentException", error.description)
        default: throw ConformanceError("Unregistered filesystem loader error: \(String(reflecting: type(of: error)))")
        }
    }
}

/// Only the actual owned temporary fixture-root prefix is projected. Every
/// relative segment, filename, line/column and diagnostic text remains exact.
/// No expected value participates, and substrings inside larger tokens survive.
struct FixturePathProjection {
    private let prefixes: [[UInt16]]
    init(root: URL) {
        let canonical = root.standardizedFileURL.resolvingSymlinksInPath()
        let paths = Set([root.path, canonical.path])
        let forms = paths.flatMap { [$0, "file:" + $0, "file://" + $0] }
        prefixes = Set(forms).sorted { $0.utf16.count > $1.utf16.count }.map { Array($0.utf16) }
    }
    func apply(_ text: String) -> String {
        let units = Array(text.utf16), marker = Array("<fixtures>".utf16)
        var result: [UInt16] = [], index = 0
        while index < units.count {
            let boundary = index == 0 || units[index - 1] <= 32 || units[index - 1] == 34 || units[index - 1] == 39
            if boundary, let prefix = prefixes.first(where: { prefix in
                index + prefix.count <= units.count && units[index..<(index + prefix.count)].elementsEqual(prefix)
                    && (index + prefix.count == units.count || units[index + prefix.count] == 47
                        || units[index + prefix.count] <= 32 || [34, 39, 58].contains(units[index + prefix.count]))
            }) {
                result.append(contentsOf: marker); index += prefix.count
            } else { result.append(units[index]); index += 1 }
        }
        return String(decoding: result, as: UTF16.self)
    }
}

/// Test-only materialization reproduces the pinned JS build recipe using the
/// archived authored bytes, including nested files and physical FIFO entries.
final class FixtureMaterializer {
    private let ownedRoot: URL
    let fixturesRoot: URL
    private let projection: FixturePathProjection
    private var known: [String: Data] = [:]

    init() throws {
        ownedRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("lokalized-swift-fixtures-" + UUID().uuidString, isDirectory: true)
        fixturesRoot = ownedRoot.appendingPathComponent("fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixturesRoot, withIntermediateDirectories: true)
        projection = FixturePathProjection(root: fixturesRoot)
    }
    deinit { try? FileManager.default.removeItem(at: ownedRoot) }
    func project(_ text: String) -> String { projection.apply(text) }

    func directory(_ row: BehavioralCase) throws -> URL {
        guard let fixture = row.fixture, let materialized = row.materializedFiles else { throw ConformanceError("Filesystem fixture lacks archived bytes") }
        let fields = try fixture.checkedObject(at: "filesystem.fixture")
        var identity = try FixtureJSONWriter.bytes(fixture)
        for name in materialized.keys.sorted() {
            identity.append(contentsOf: FixtureJSONWriter.quote(name.string).utf8)
            let data = materialized[name]!
            identity.append(contentsOf: String(data.count).utf8); identity.append(0); identity.append(data)
        }
        let id = row.fixtureID ?? "native-fixture-" + row.id
        try requireRelativePath(id)
        let directory = fixturesRoot.appendingPathComponent(id)
        if let previous = known[id] {
            guard previous == identity else { throw ConformanceError("Fixture ID reused with different authored inputs") }; return directory
        }
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch try fields.string("pathShape", at: "filesystem.fixture") {
        case "absent":
            guard materialized.isEmpty else { throw ConformanceError("Absent path fixture unexpectedly has file bytes") }
        case "regular-file":
            guard materialized.isEmpty else { throw ConformanceError("Regular-file path fixture unexpectedly has child bytes") }
            try writeExactBytes(FixtureJSONWriter.bytes(.object([.test("Key.A", .string("a"))])), path: directory.path)
        case "directory":
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let entries = try fields.value("entries", at: "filesystem.fixture").checkedObject(at: "filesystem.entries")
            var fileNames = Set<ExactString>()
            for name in ["files", "rawFiles", "rawFilesBase64"] {
                fileNames.formUnion(try fields.value(name, at: "filesystem.fixture").checkedObject(at: name).keys)
            }
            for (name, value) in entries {
                try requireRelativePath(name.string)
                let entry = try value.checkedObject(at: "filesystem.entry", allowed: ["kind", "files"])
                let location = directory.appendingPathComponent(name.string)
                switch try entry.string("kind", at: "filesystem.entry") {
                case "directory":
                    try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
                    if let files = entry["files"] {
                        for child in try files.checkedObject(at: "filesystem.entry.files").keys {
                            try requireRelativePath(child.string); fileNames.insert(ExactString(name.string + "/" + child.string))
                        }
                    }
                case "fifo":
                    guard entry["files"] == nil else { throw ConformanceError("FIFO fixture has child files") }
                    guard location.path.withCString({ mkfifo($0, 0o600) }) == 0 else { throw ConformanceError("Could not create actual FIFO fixture: errno \(errno)") }
                default: throw ConformanceError("Unknown filesystem fixture entry kind")
                }
            }
            guard fileNames == Set(materialized.keys) else { throw ConformanceError("Filesystem archived-file inventory disagrees with authored source inputs") }
            for name in fileNames.sorted() {
                try requireRelativePath(name.string)
                let file = directory.appendingPathComponent(name.string)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try writeExactBytes(materialized[name]!, path: directory.path + "/" + name.string)
            }
        default: throw ConformanceError("Unknown filesystem fixture path shape")
        }
        known[id] = identity
        return directory
    }

    private func requireRelativePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }), !path.utf16.contains(0) else {
            throw ConformanceError("Invalid owned fixture relative path")
        }
    }

    // Foundation's filesystem representation decomposes some filename text.
    // The pinned Node/Java recipe writes authored UTF-8 names directly; use the
    // same bytes here, without changing the native loader's observed diagnostics.
    private func writeExactBytes(_ bytes: Data, path: String) throws {
        let descriptor = path.withCString { open($0, O_WRONLY | O_CREAT | O_TRUNC, 0o600) }
        guard descriptor >= 0 else { throw ConformanceError("Could not write owned fixture file: errno \(errno)") }
        defer { close(descriptor) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw ConformanceError("Could not write archived fixture bytes: errno \(errno)") }
                offset += written
            }
        }
    }
}

private final class LoadWarningRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [LocalizedStringWarning] = []
    func append(_ value: LocalizedStringWarning) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var snapshot: [LocalizedStringWarning] { lock.lock(); defer { lock.unlock() }; return values }
}
