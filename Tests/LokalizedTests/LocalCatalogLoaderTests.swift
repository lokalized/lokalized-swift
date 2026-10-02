import Foundation
import Darwin
import XCTest
import Lokalized

final class LocalCatalogLoaderTests: XCTestCase {
    private let warningFile = #"{"A":{"translation":"{{n}}","placeholders":{"n":{"value":"count","translations":{"CARDINALITY_ONE":"one"}}}}}"#
    private func directory(_ body: (URL) throws -> Void) throws {
        let pointer = try XCTUnwrap(FileManager.default.temporaryDirectory.path.withCString { realpath($0, nil) })
        let temporaryDirectory = URL(fileURLWithPath: String(cString: pointer), isDirectory: true)
        free(pointer)
        let root = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
    private func write(_ text: String, _ name: String, _ root: URL) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(name))
    }
    func testCallerStreamIsOpenedButNeverClosedAndReadsCurrentPosition() throws {
        let input = LoaderProbeStream(Data(#"{"x":"y"}"#.utf8), chunk: 1)
        let file = try LocalizedStringLoader.parse(input, locale: "en", source: "stream")
        XCTAssertEqual(file.strings.first?.translation, "y")
        XCTAssertEqual(file.sources, ["stream"])
        XCTAssertEqual(input.openCount, 1); XCTAssertEqual(input.closeCount, 0)
        let opened = LoaderProbeStream(Data("xx{}".utf8), chunk: 1)
        opened.open(); var byte: UInt8 = 0
        _ = opened.read(&byte, maxLength: 1); _ = opened.read(&byte, maxLength: 1)
        XCTAssertTrue(try LocalizedStringLoader.parse(opened, locale: "en").strings.isEmpty)
        XCTAssertEqual(opened.openCount, 1); XCTAssertEqual(opened.closeCount, 0)
    }
    func testInvalidLocaleRefusesBeforeOpeningStreamAndResolvingFile() throws {
        let input = LoaderProbeStream(Data("{}".utf8))
        XCTAssertThrowsError(try LocalizedStringLoader.parse(input, locale: "en-!")) { XCTAssertTrue($0 is LocaleTagError) }
        XCTAssertEqual(input.openCount, 0); XCTAssertEqual(input.requests, [])
        XCTAssertThrowsError(try LocalizedStringLoader.parse(file: URL(fileURLWithPath: "/does/not/exist"), locale: "en-!")) {
            XCTAssertTrue($0 is LocaleTagError)
        }
    }
    func testBoundedReadRetainsOnlyOneExtraByteAndAggregateFailureWins() throws {
        let input = LoaderProbeStream(Data(repeating: 32, count: 100), chunk: 1)
        let limits = try LocalizedStringLoadingOptions(maximumInputBytes: 3)
        XCTAssertThrowsError(try LocalizedStringLoader.parse(input, locale: "en", source: "s", loadingOptions: limits)) {
            XCTAssertEqual(($0 as? StringsParseError)?.message, "s: localized strings resource exceeds the maximum size of 3 bytes")
        }
        XCTAssertEqual(input.offset, 4); XCTAssertEqual(input.closeCount, 0)
        let simultaneous = try LocalizedStringLoadingOptions(maximumInputBytes: 3, maximumTotalInputBytes: 3)
        XCTAssertThrowsError(try LocalizedStringLoader.parse(LoaderProbeStream(Data(repeating: 32, count: 100)), locale: "en", source: "s", loadingOptions: simultaneous)) {
            XCTAssertEqual(($0 as? StringsParseError)?.message, "s: localized strings load exceeds the aggregate maximum of 3 input bytes")
        }
    }
    func testStrictUTF8BOMAndByteInputsDoNotChargeReaderCharacters() throws {
        let limits = try LocalizedStringLoadingOptions(maximumReaderCharacters: 1)
        let input = Data([0xEF, 0xBB, 0xBF]) + Data(#"{"é":"💡"}"#.utf8)
        XCTAssertEqual(try LocalizedStringLoader.parse(InputStream(data: input), locale: "en", loadingOptions: limits).strings.first?.translation, "💡")
        XCTAssertThrowsError(try LocalizedStringLoader.parse(InputStream(data: Data([0xC0, 0xAF])), locale: "en", source: "invalid")) {
            let failure = $0 as? StringsParseError
            XCTAssertEqual(failure?.message, "invalid: localized strings resource is not valid UTF-8")
            XCTAssertNotNil(failure?.cause)
        }
    }
    func testReadFailureKeepsImmediateCauseAndCallerOwnership() throws {
        let cause = LoaderIdentityError()
        let input = LoaderProbeStream(Data(), failure: cause)
        XCTAssertThrowsError(try LocalizedStringLoader.parse(input, locale: "en", source: "s")) {
            let failure = $0 as? LocalizedStringLoadingError
            XCTAssertEqual(failure?.message, "Unable to load localized strings resource contents for s")
            XCTAssertTrue((failure?.cause as AnyObject?) === cause)
        }
        XCTAssertEqual(input.closeCount, 0)
    }
    func testNonrecursiveFiltersAndCaseInsensitiveJSONExtension() throws {
        try directory { root in
            try write(#"{"en":"English"}"#, "en", root)
            try write(#"{"fr":"French"}"#, "fr.JSON", root)
            for name in [".de.json", "README.txt", "de.txt", "zz"] { try write("invalid", name, root) }
            try FileManager.default.createDirectory(at: root.appendingPathComponent("invalid.json"), withIntermediateDirectories: false)
            try write("invalid", "en.json", root.appendingPathComponent("invalid.json"))
            let files = try LocalizedStringLoader.loadFromDirectory(root)
            XCTAssertEqual(Set(files.keys), [try LocaleTag("en"), try LocaleTag("fr")])
        }
    }
    func testInvalidJSONFilenameIsStrictAndDeterministic() throws {
        try directory { root in
            try write("{}", "zz.json", root); try write("{}", "notes.json", root)
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromDirectory(root)) {
                XCTAssertTrue(($0 as? LocalizedStringLoadingError)?.message.hasPrefix("File 'notes.json' ends with .json") == true)
            }
        }
    }
    func testJSONSuffixUsesASCIIBytesBesideUnicodePrependAndCombiningMarks() throws {
        for name in ["xx\u{600}.json", "xx\u{301}.JsOn"] {
            try directory { root in
                try write("{}", name, root)
                XCTAssertThrowsError(try LocalizedStringLoader.loadFromDirectory(root)) {
                    XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.kind, .invalidResource)
                    XCTAssertTrue(($0 as? LocalizedStringLoadingError)?.message.contains("ends with .json") == true)
                }
            }
        }
    }
    func testDuplicateIdentityWinsBeforeSecondFileParsing() throws {
        try directory { root in
            try write("{}", "en", root); try write("invalid", "en.json", root)
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromDirectory(root)) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.message, "Duplicate localized strings file for locale 'en' found at '\(root.path)/en.json'")
            }
        }
    }
    func testDifferentTypedIdentitiesWithSameRenderedTagRefuseAfterParsing() throws {
        try directory { root in
            try write("{}", "nn-NO", root); try write("{}", "no-NO-x-lvariant-NY", root)
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromDirectory(root)) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.message, "Duplicate locale key rendering as language tag 'nn-NO'")
            }
        }
    }
    func testSymlinkProvenanceDanglingAndFIFORefusal() throws {
        try directory { root in
            let storage = root.appendingPathComponent("storage")
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)
            try write(#"{"x":"linked"}"#, "actual", storage)
            let actual = storage.appendingPathComponent("actual")
            let link = root.appendingPathComponent("en.json")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)
            let file = try LocalizedStringLoader.loadFromDirectory(root)[LocaleTag("en")]
            XCTAssertEqual(file?.sources, [actual.path])
            try FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("missing"))
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromDirectory(root)) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.message, "Unable to determine canonical path for localized strings file \(link.path)")
                XCTAssertNotNil(($0 as? LocalizedStringLoadingError)?.cause)
            }
            try FileManager.default.removeItem(at: link)
            XCTAssertEqual(link.path.withCString { mkfifo($0, 0o600) }, 0)
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromDirectory(root)) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.message, "\(link.path) is not a regular file")
            }
        }
    }
    func testCanonicalSymlinkTargetInvalidUTF8CannotSelectRepairedFilename() throws {
        try directory { root in
            let invalidPath = Array(root.path.utf8) + [47, 0xFF, 0]
            let replacement = root.appendingPathComponent("\u{FFFD}")
            try Data(#"{"x":"different file"}"#.utf8).write(to: replacement)
            let fd = invalidPath.withUnsafeBytes {
                Darwin.open($0.baseAddress!.assumingMemoryBound(to: CChar.self), O_WRONLY | O_CREAT | O_TRUNC, 0o600)
            }
            guard fd >= 0 else {
                throw XCTSkip("Raw invalid-UTF8 path fixture is unavailable in this execution environment (errno \(errno))")
            }
            defer { invalidPath.withUnsafeBytes { _ = unlink($0.baseAddress!.assumingMemoryBound(to: CChar.self)) } }
            let contents = Array(#"{"x":"actual raw target"}"#.utf8)
            XCTAssertEqual(contents.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }, contents.count)
            XCTAssertEqual(Darwin.close(fd), 0)
            let link = root.appendingPathComponent("en.json")
            XCTAssertEqual(invalidPath.withUnsafeBytes { target in
                link.path.withCString { symlink(target.baseAddress!.assumingMemoryBound(to: CChar.self), $0) }
            }, 0)
            for operation in [
                { _ = try LocalizedStringLoader.parse(file: link, locale: "en") },
                { _ = try LocalizedStringLoader.loadFromDirectory(root) },
                { _ = try LocalizedStringLoader.loadFromResources([try LocaleTag("en"): link]) }
            ] {
                XCTAssertThrowsError(try operation()) {
                    XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.kind, .invalidResource)
                    XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.message,
                                   "Canonical path for localized strings file \(link.path) is not valid UTF-8")
                }
            }
        }
    }
    func testCanonicalPathByteBoundaryStrictlyRejectsInvalidUTF8WithoutRepair() throws {
        for bytes: [UInt8] in [[47, 0xFF], [47, 0xC0, 0xAF], [47, 0xED, 0xA0, 0x80]] {
            XCTAssertThrowsError(try bytes.withUnsafeBufferPointer {
                try LocalCatalogLoader.decodeCanonicalPath($0, source: "/requested/en.json")
            }) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.kind, .invalidResource)
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.source, "/requested/en.json")
            }
        }
        for path in ["/é/e\u{301}", "/\u{FFFD}"] {
            let decoded = try Array(path.utf8).withUnsafeBufferPointer {
                try LocalCatalogLoader.decodeCanonicalPath($0, source: "/requested/en.json")
            }
            XCTAssertEqual(ExactString(decoded), ExactString(path))
        }
    }
    func testAggregateBytesFilesNodesAndWarningsSpanExplicitResources() throws {
        try directory { root in
            try write(#"{"A":"a"}"#, "first", root); try write(#"{"B":"b"}"#, "second", root)
            let resources = [try LocaleTag("en"): root.appendingPathComponent("first"), try LocaleTag("fr"): root.appendingPathComponent("second")]
            for limits in [try LocalizedStringLoadingOptions(maximumTotalInputBytes: 10), try LocalizedStringLoadingOptions(maximumTranslationNodes: 1)] {
                XCTAssertThrowsError(try LocalizedStringLoader.loadFromResources(resources, loadingOptions: limits)) {
                    XCTAssertTrue(($0 as? StringsParseError)?.source.hasSuffix("/second") == true)
                }
            }
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromResources(resources, loadingOptions: .init(maximumLocalizedStringsFiles: 1))) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.kind, .invalidResource)
            }
            try write(warningFile, "first", root); try write(warningFile, "second", root)
            let recorder = LoaderWarnings()
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromResources(resources, warningHandler: recorder.append, loadingOptions: .init(maximumWarnings: 1))) {
                XCTAssertTrue(($0 as? StringsParseError)?.message.hasSuffix("aggregate maximum of 1 warnings") == true)
            }
            XCTAssertEqual(recorder.values.count, 1)
            let files = try LocalizedStringLoader.loadFromResources(resources)
            XCTAssertEqual(files[try LocaleTag("en")]?.warnings.count, 1)
            XCTAssertEqual(files[try LocaleTag("fr")]?.warnings.count, 1)
            XCTAssertTrue(files[try LocaleTag("fr")]?.warnings.first?.source.hasSuffix("/second") == true)
        }
    }
    func testDirectoryFileAndDiscoveryBudgetsIncludeIgnoredActualEntries() throws {
        try directory { root in
            try write(warningFile, "en", root); try write("{}", "fr", root); try write("ignored", ".hidden", root)
            let warnings = LoaderWarnings()
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromDirectory(root, warningHandler: warnings.append, loadingOptions: .init(maximumDiscoveryEntries: 2))) {
                XCTAssertEqual(($0 as? StringsParseError)?.message, "filesystem directory '\(root.path)': localized strings load exceeds the aggregate maximum of 2 discovery entries")
            }
            XCTAssertTrue(warnings.values.isEmpty)
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromDirectory(root, loadingOptions: .init(maximumLocalizedStringsFiles: 1))) {
                XCTAssertTrue(($0 as? StringsParseError)?.source.hasSuffix("/fr") == true)
            }
        }
    }
    func testWarningHandlerErrorIdentityAndReentry() throws {
        try directory { root in
            try write(warningFile, "en", root)
            let cause = LoaderIdentityError()
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromDirectory(root, warningHandler: { _ in
                XCTAssertTrue(try LocalizedStringLoader.parse("{}", locale: "en").strings.isEmpty)
                throw cause
            })) { XCTAssertTrue(($0 as AnyObject) === cause) }
        }
    }
    func testExplicitMappingsPreflightBeforeOpeningAndMissingDirectoryErrors() throws {
        try directory { root in
            let absent = root.appendingPathComponent("absent")
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromResources([try LocaleTag("en"): absent, try LocaleTag("fr"): URL(string: "https://example.com/catalog")!])) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.kind, .invalidResource)
            }
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromResources([LocaleTag.forLanguageTag("en-x-lvariant-NY"): absent])) {
                XCTAssertTrue($0 is LocaleTagError)
            }
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromDirectory(absent)) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.message, "Location '\(absent.path)' does not exist")
            }
            try write("{}", "regular", root)
            let regular = root.appendingPathComponent("regular")
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromDirectory(regular)) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.message, "Location '\(regular.path)' exists but is not a directory")
            }
        }
    }
    func testExplicitCaseFoldedVariantCollisionRemainsAfterParsingAndWarnings() throws {
        try directory { root in
            try write(warningFile, "first", root)
            try write("not JSON", "second", root)
            let resources = [try LocaleTag("en-ABCDE"): root.appendingPathComponent("first"),
                             try LocaleTag("en-abcde"): root.appendingPathComponent("second")]
            let beforeFailure = LoaderWarnings()
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromResources(resources, warningHandler: beforeFailure.append)) {
                XCTAssertTrue($0 is StringsParseError)
                XCTAssertEqual(($0 as? StringsParseError)?.source, root.appendingPathComponent("second").path)
            }
            XCTAssertEqual(beforeFailure.values.count, 1)
            try write(warningFile, "second", root)
            let beforeCollision = LoaderWarnings()
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromResources(resources, warningHandler: beforeCollision.append)) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.message,
                               "Duplicate locale key rendering as language tag 'en-abcde'")
            }
            XCTAssertEqual(beforeCollision.values.count, 2)
        }
    }
}

private final class LoaderIdentityError: Error, Sendable {}
private final class LoaderWarnings: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LocalizedStringWarning] = []
    var values: [LocalizedStringWarning] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ warning: LocalizedStringWarning) { lock.lock(); defer { lock.unlock() }; storage.append(warning) }
}
private final class LoaderProbeStream: InputStream {
    let bytes: Data, chunk: Int, failure: (any Error)?
    var offset = 0, openCount = 0, closeCount = 0
    var requests: [Int] = []
    private var status: Stream.Status = .notOpen
    init(_ bytes: Data, chunk: Int = 8_192, failure: (any Error)? = nil) {
        self.bytes = bytes; self.chunk = chunk; self.failure = failure
        super.init(data: Data())
    }
    override var streamStatus: Stream.Status { status }
    override var streamError: (any Error)? { failure }
    override func open() { openCount += 1; status = .open }
    override func close() { closeCount += 1; status = .closed }
    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
        requests.append(maxLength)
        if failure != nil { return -1 }
        let count = min(maxLength, chunk, bytes.count - offset)
        if count == 0 { status = .atEnd; return 0 }
        bytes.copyBytes(to: buffer, from: offset..<(offset + count))
        offset += count; return count
    }
}
