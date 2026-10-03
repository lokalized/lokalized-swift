import Foundation
import Darwin
import Lokalized

// Owned qualification fixtures must be writable in an application sandbox and
// use the same POSIX-canonical origin spelling as the public local-file loader.
// Foundation's resolvingSymlinksInPath does not resolve every /var alias.
func qualificationTemporaryDirectory() throws -> URL {
    guard let path = FileManager.default.temporaryDirectory.path.withCString({ realpath($0, nil) }) else {
        throw ConformanceError("Unable to resolve the caller's temporary directory")
    }
    defer { free(path) }
    return URL(fileURLWithPath: String(cString: path), isDirectory: true)
}

/// Real local-file and caller-stream checks, independent of frozen corpus
/// expectations and XCTest. Resources are created in one owned temporary tree.
enum LocalLoadingQualification {
    static func run() throws -> Int {
        var checks = 0
        func expect(_ condition: @autoclosure () throws -> Bool, _ detail: String) throws {
            guard try condition() else { throw ConformanceError("Local loading qualification: \(detail)") }
            checks += 1
        }
        func failure(_ operation: () throws -> Void) throws -> any Error {
            do { try operation() }
            catch { return error }
            throw ConformanceError("Expected local loading refusal")
        }
        let temporaryDirectory = try qualificationTemporaryDirectory()
        let root = temporaryDirectory.appendingPathComponent("lokalized-qualification-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func directory(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        }
        func write(_ text: String, _ name: String, in directory: URL) throws -> URL {
            let url = directory.appendingPathComponent(name)
            try Data(text.utf8).write(to: url); return url
        }
        let en = try LocaleTag("en"), fr = try LocaleTag("fr")
        let direct = QualificationInputStream(Data(#"{"é":"NFC","e\u0301":"NFD"}"#.utf8), chunk: 1)
        let parsed = try LocalizedStringLoader.parse(direct, locale: "en", source: "caller")
        try expect(parsed.strings.count == 2, "UTF16-distinct stream keys")
        try expect(parsed.sources == ["caller"], "caller source")
        try expect(direct.opens == 1 && direct.closes == 0, "caller stream retained")
        let invalidLocale = QualificationInputStream(Data("{}".utf8))
        try expect(try failure { _ = try LocalizedStringLoader.parse(invalidLocale, locale: "en-!") } is LocaleTagError, "strict locale error")
        try expect(invalidLocale.opens == 0 && invalidLocale.offset == 0, "invalid locale before stream open")
        let bounded = QualificationInputStream(Data(repeating: 32, count: 100), chunk: 1)
        let byteLimit = try LocalizedStringLoadingOptions(maximumInputBytes: 3)
        let boundedFailure = try failure { _ = try LocalizedStringLoader.parse(bounded, locale: "en", source: "bounded", loadingOptions: byteLimit) }
        try expect((boundedFailure as? StringsParseError)?.message == "bounded: localized strings resource exceeds the maximum size of 3 bytes", "resource byte refusal")
        try expect(bounded.offset == 4 && bounded.closes == 0, "read at most one extra byte")
        let combined = try LocalizedStringLoadingOptions(maximumInputBytes: 3, maximumTotalInputBytes: 3)
        let aggregateFailure = try failure { _ = try LocalizedStringLoader.parse(QualificationInputStream(Data(repeating: 32, count: 100)), locale: "en", source: "bounded", loadingOptions: combined) }
        try expect((aggregateFailure as? StringsParseError)?.message == "bounded: localized strings load exceeds the aggregate maximum of 3 input bytes", "aggregate before resource refusal")
        let utf8Failure = try failure { _ = try LocalizedStringLoader.parse(InputStream(data: Data([0xC0, 0xAF])), locale: "en") }
        try expect((utf8Failure as? StringsParseError)?.cause != nil, "strict UTF8 cause retained")
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data("{}".utf8)
        try expect(try LocalizedStringLoader.parse(InputStream(data: bom), locale: "en", loadingOptions: .init(maximumReaderCharacters: 1)).strings.isEmpty, "byte input bypasses character cap")
        let ioCause = QualificationLoadError()
        let failed = QualificationInputStream(Data(), failure: ioCause)
        let ioFailure = try failure { _ = try LocalizedStringLoader.parse(failed, locale: "en") }
        try expect(ioFailure is LocalizedStringLoadingError, "transport error type")
        try expect(((ioFailure as? LocalizedStringLoadingError)?.cause as AnyObject?) === ioCause, "transport immediate cause identity")
        try expect(failed.closes == 0, "failed caller stream retained")

        let files = try directory("filters")
        let english = try write(#"{"hello":"English"}"#, "en", in: files)
        _ = try write(#"{"hello":"French"}"#, "fr.JSON", in: files)
        for name in [".de.json", "de.txt", "README.txt", "zz"] { _ = try write("invalid", name, in: files) }
        try FileManager.default.createDirectory(at: files.appendingPathComponent("invalid.json"), withIntermediateDirectories: false)
        let loaded = try LocalizedStringLoader.loadFromDirectory(files)
        try expect(Set(loaded.keys) == [en, fr], "nonrecursive literal-name filters")
        try expect(loaded[en]?.strings.first?.translation == "English", "extensionless file")
        try expect(loaded[fr]?.strings.first?.translation == "French", "ASCII-insensitive JSON suffix")
        try expect(loaded[en]?.sources == [english.path], "canonical resource origin")
        let empty = try directory("empty")
        try expect(try LocalizedStringLoader.loadFromDirectory(empty).isEmpty, "empty directory")
        try expect(try LocalizedStringLoader.loadFromResources([:]).isEmpty, "empty explicit resource map")
        let missing = root.appendingPathComponent("missing")
        let missingFailure = try failure { _ = try LocalizedStringLoader.loadFromDirectory(missing) }
        try expect((missingFailure as? LocalizedStringLoadingError)?.message == "Location '\(missing.path)' does not exist", "absent directory diagnostic")
        let fileDirectoryFailure = try failure { _ = try LocalizedStringLoader.loadFromDirectory(english) }
        try expect((fileDirectoryFailure as? LocalizedStringLoadingError)?.message == "Location '\(english.path)' exists but is not a directory", "regular-file directory diagnostic")
        let invalidNames = try directory("invalid-names")
        _ = try write("{}", "zz.json", in: invalidNames); _ = try write("{}", "notes.json", in: invalidNames)
        let nameFailure = try failure { _ = try LocalizedStringLoader.loadFromDirectory(invalidNames) }
        try expect((nameFailure as? LocalizedStringLoadingError)?.message.hasPrefix("File 'notes.json'") == true, "deterministic UTF8 filename refusal")
        let prepend = try directory("prepend")
        _ = try write("{}", "xx\u{600}.json", in: prepend)
        try expect((try failure { _ = try LocalizedStringLoader.loadFromDirectory(prepend) } as? LocalizedStringLoadingError)?.kind == .invalidResource, "suffix beside Unicode Prepend")
        let duplicate = try directory("duplicate")
        _ = try write("{}", "en", in: duplicate); _ = try write("invalid", "en.json", in: duplicate)
        try expect((try failure { _ = try LocalizedStringLoader.loadFromDirectory(duplicate) } as? LocalizedStringLoadingError)?.kind == .duplicateLocale, "identity duplicate before second parse")
        let rendered = try directory("rendered")
        _ = try write("{}", "nn-NO", in: rendered); _ = try write("{}", "no-NO-x-lvariant-NY", in: rendered)
        try expect((try failure { _ = try LocalizedStringLoader.loadFromDirectory(rendered) } as? LocalizedStringLoadingError)?.message == "Duplicate locale key rendering as language tag 'nn-NO'", "typed rendered collision")

        let linkDirectory = try directory("links")
        let target = try write(#"{"x":"linked"}"#, "target", in: root)
        let link = linkDirectory.appendingPathComponent("en.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try expect(try LocalizedStringLoader.loadFromDirectory(linkDirectory)[en]?.sources == [target.path], "symlink follows canonical provenance")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)
        let dangling = try failure { _ = try LocalizedStringLoader.loadFromDirectory(linkDirectory) }
        try expect((dangling as? LocalizedStringLoadingError)?.cause is POSIXError, "dangling link immediate cause")
        try FileManager.default.removeItem(at: link)
        try expect(link.path.withCString { mkfifo($0, 0o600) } == 0, "FIFO fixture created")
        try expect((try failure { _ = try LocalizedStringLoader.loadFromDirectory(linkDirectory) } as? LocalizedStringLoadingError)?.message == "\(link.path) is not a regular file", "FIFO refused before open")

        let warningText = #"{"A":{"translation":"{{n}}","placeholders":{"n":{"value":"count","translations":{"CARDINALITY_ONE":"one"}}}}}"#
        let shared = try directory("aggregate")
        let first = try write(warningText, "en", in: shared)
        let second = try write(warningText, "fr", in: shared)
        let resources = [en: first, fr: second]
        let warnings = QualificationWarnings()
        let discovery = try failure { _ = try LocalizedStringLoader.loadFromDirectory(shared, warningHandler: warnings.append, loadingOptions: .init(maximumDiscoveryEntries: 1)) }
        try expect((discovery as? StringsParseError)?.message.hasSuffix("aggregate maximum of 1 discovery entries") == true, "bounded discovery refusal")
        try expect(warnings.values.isEmpty, "discovery refusal before warning delivery")
        let warningFailure = try failure { _ = try LocalizedStringLoader.loadFromResources(resources, warningHandler: warnings.append, loadingOptions: .init(maximumWarnings: 1)) }
        try expect((warningFailure as? StringsParseError)?.source.hasSuffix("/fr") == true, "shared warning budget source")
        try expect(warnings.values.count == 1, "refused warning not delivered")
        let complete = try LocalizedStringLoader.loadFromResources(resources)
        try expect(complete[en]?.warnings.count == 1 && complete[fr]?.warnings.count == 1, "per-file warning snapshots")
        try expect(complete[fr]?.warnings.first?.source.hasSuffix("/fr") == true, "warning provenance does not leak previous file")
        let callbackError = QualificationLoadError()
        let callbackFailure = try failure { _ = try LocalizedStringLoader.loadFromResources(resources, warningHandler: { _ in
            _ = try LocalizedStringLoader.parse("{}", locale: "en")
            throw callbackError
        }) }
        try expect((callbackFailure as AnyObject) === callbackError, "warning error identity and reentry")
        let fileCap = try failure { _ = try LocalizedStringLoader.loadFromResources(resources, loadingOptions: .init(maximumLocalizedStringsFiles: 1)) }
        try expect((fileCap as? LocalizedStringLoadingError)?.kind == .invalidResource, "explicit mapping preflight file cap")
        let directoryCap = try failure { _ = try LocalizedStringLoader.loadFromDirectory(shared, loadingOptions: .init(maximumLocalizedStringsFiles: 1)) }
        try expect((directoryCap as? StringsParseError)?.source.hasSuffix("/fr") == true, "directory aggregate file cap")
        let nodeCap = try failure { _ = try LocalizedStringLoader.loadFromResources(resources, loadingOptions: .init(maximumTranslationNodes: 2)) }
        try expect((nodeCap as? StringsParseError)?.source.hasSuffix("/fr") == true, "aggregate nodes include placeholder definitions")
        let totalCap = try failure { _ = try LocalizedStringLoader.loadFromResources(resources, loadingOptions: .init(maximumTotalInputBytes: warningText.utf8.count)) }
        try expect((totalCap as? StringsParseError)?.source.hasSuffix("/fr") == true, "aggregate actual input bytes")
        let preflight = try failure { _ = try LocalizedStringLoader.loadFromResources([en: missing, fr: URL(string: "https://example.com/catalog")!]) }
        try expect((preflight as? LocalizedStringLoadingError)?.kind == .invalidResource, "all explicit URLs checked before IO")
        let malformed = try failure { _ = try LocalizedStringLoader.loadFromResources([LocaleTag.forLanguageTag("en-x-lvariant-NY"): missing]) }
        try expect(malformed is LocaleTagError, "typed locale rebuildability preflight")
        return checks
    }
}

private final class QualificationLoadError: Error, Sendable {}
private final class QualificationWarnings: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LocalizedStringWarning] = []
    var values: [LocalizedStringWarning] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ warning: LocalizedStringWarning) { lock.lock(); defer { lock.unlock() }; storage.append(warning) }
}
private final class QualificationInputStream: InputStream {
    let bytes: Data, chunk: Int, failure: (any Error)?
    var offset = 0, opens = 0, closes = 0
    private var status: Stream.Status = .notOpen
    init(_ bytes: Data, chunk: Int = 8_192, failure: (any Error)? = nil) {
        self.bytes = bytes; self.chunk = chunk; self.failure = failure; super.init(data: Data())
    }
    override var streamStatus: Stream.Status { status }
    override var streamError: (any Error)? { failure }
    override func open() { opens += 1; status = .open }
    override func close() { closes += 1; status = .closed }
    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
        if failure != nil { return -1 }
        let count = min(maxLength, chunk, bytes.count - offset)
        if count == 0 { status = .atEnd; return 0 }
        bytes.copyBytes(to: buffer, from: offset..<(offset + count)); offset += count
        return count
    }
}
