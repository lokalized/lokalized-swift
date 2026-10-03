import Foundation
import Darwin
import Lokalized

/// Native carrier controls. These execute public APIs against owned resources;
/// no corpus observation configures a load or turns a JVM carrier into a pass.
public enum LoaderBoundaryQualification {
    public struct Report: Encodable, Sendable {
        public let scope = "native-local-loader-boundaries"
        public let status = "passed"
        public let passed: [String]
        public let observations: [String: String]
    }

    public static func run() throws -> Report {
        var passed: [String] = [], observations: [String: String] = [:]
        func check(_ id: String, _ condition: @autoclosure () throws -> Bool, _ observation: String) throws {
            guard try condition(), !passed.contains(id) else { throw ConformanceError("Loader boundary failed: " + id + "; " + observation) }
            passed.append(id); observations[id] = observation
        }
        func refused(_ action: () throws -> Void) throws -> any Error {
            do { try action() } catch { return error }
            throw ConformanceError("Loader boundary expected a refusal")
        }
        let root = try qualificationTemporaryDirectory()
            .appendingPathComponent("lokalized-carriers-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func directory(_ path: String, under parent: URL) throws -> URL {
            let url = parent.appendingPathComponent(path, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func write(_ text: String, _ name: String, under parent: URL) throws -> URL {
            let url = parent.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url); return url
        }
        func bundle(_ name: String) throws -> (Bundle, URL) {
            let location = try directory(name + ".bundle", under: root)
            #if os(macOS)
            let contents = try directory("Contents", under: location)
            let resources = try directory("Resources", under: contents)
            #else
            let contents = location, resources = location
            #endif
            let info: [String: String] = ["CFBundleIdentifier": "com.lokalized.qualification." + UUID().uuidString,
                "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            guard let value = Bundle(url: location) else { throw ConformanceError("Unable to construct owned Bundle") }
            return (value, resources)
        }
        let en = try LocaleTag("en"), fr = try LocaleTag("fr")
        let (first, firstRoot) = try bundle("First"), (second, secondRoot) = try bundle("Second")
        let firstDir = try directory("Lokalized", under: firstRoot)
        let secondDir = try directory("Lokalized", under: secondRoot)
        let english = try write(#"{"hello":"first","é":"NFC","e\u0301":"NFD"}"#, "en", under: firstDir)
        _ = try write(#"{"hello":"second"}"#, "en", under: secondDir)
        let a = try LocalizedStringLoader.loadFromBundle(first), b = try LocalizedStringLoader.loadFromBundle(second)
        try check("explicit-bundle-context", a[en]?.strings.first?.translation == "first" && b[en]?.strings.first?.translation == "second",
            "Two explicit bundles keep identical resource paths independent")
        guard let canonicalBytes = english.path.withCString({ realpath($0, nil) }) else { throw ConformanceError("Unable to canonicalize native control") }
        let canonicalEnglish = String(cString: canonicalBytes); free(canonicalBytes)
        try check("canonical-origins-and-exact-keys", a[en]?.sources == [canonicalEnglish]
            && Set(a[en]!.strings.map(\.key)) == Set(["hello", "é", ExactString("e\u{0301}")]),
            "POSIX canonical origin and three UTF-16-distinct keys retained")
        let absent = try refused { _ = try LocalizedStringLoader.loadFromBundle(first, directory: "Absent") }
        try check("bundle-missing-exact-directory", (absent as? LocalizedStringLoadingError)?.message.hasSuffix("/Absent' does not exist") == true,
            "Missing exact path refuses; no bundle or prefix search")
        _ = try directory("Empty", under: firstRoot)
        try check("bundle-empty-directory", try LocalizedStringLoader.loadFromBundle(first, directory: "Empty").isEmpty,
            "Existing empty directory returns an empty catalog map")
        let notDirectory = try refused { _ = try LocalizedStringLoader.loadFromBundle(first, directory: "Lokalized/en") }
        try check("bundle-file-not-directory", (notDirectory as? LocalizedStringLoadingError)?.message.hasSuffix("exists but is not a directory") == true,
            "A file cannot impersonate a package directory")
        var invalidPathsRefused = true
        for path in ["", "/Lokalized", "Lokalized/", "Lokalized//en", ".", "../Lokalized", "Lokalized\\en", "Lokalized\u{0}"] {
            let error = try refused { _ = try LocalizedStringLoader.loadFromBundle(first, directory: path) }
            invalidPathsRefused = invalidPathsRefused && (error as? LocalizedStringLoadingError)?.kind == .invalidResource
        }
        try check("bundle-literal-path-validation", invalidPathsRefused,
            "Eight empty/absolute/traversal/backslash/NUL path shapes refused before acquisition")
        _ = try write("{}", "META-INF/versions/9/en", under: firstRoot)
        try check("bundle-has-no-jvm-reserved-namespace", try LocalizedStringLoader.loadFromBundle(first, directory: "META-INF/versions/9")[en]?.strings.isEmpty == true,
            "META-INF/versions is a literal Apple resource path, without JAR overlay semantics")
        let hidden = try write(#"{"named":"hidden"}"#, "Payloads/.catalog", under: firstRoot)
        let named = try LocalizedStringLoader.loadFromBundle(first, resourcePathsByLocale: [fr: "Payloads/.catalog"])
        try check("explicit-mapping-bypasses-filename-rules", named[fr]?.locale == "fr" && named[fr]?.strings.first?.translation == "hidden"
            && named[fr]?.sources == [hidden.path], "Explicit caller locale loads a hidden arbitrary filename literally")
        _ = try write(#"{"key":"literal"}"#, "Payloads/en.lproj/catalog", under: firstRoot)
        try check("explicit-lproj-remains-literal", try LocalizedStringLoader.loadFromBundle(first,
            resourcePathsByLocale: [fr: "Payloads/en.lproj/catalog"])[fr]?.strings.first?.translation == "literal",
            "An explicit en.lproj path under a French caller locale receives no Apple language selection")
        let repeated = try write(#"{"k":"same"}"#, "repeated", under: root)
        let repeatedSize = Data(#"{"k":"same"}"#.utf8).count
        let repeatedError = try refused { _ = try LocalizedStringLoader.loadFromResources([en: repeated, fr: repeated],
            loadingOptions: .init(maximumTotalInputBytes: repeatedSize)) }
        try check("mapping-repeated-resource-charges-bytes", (repeatedError as? StringsParseError)?.message.hasSuffix("aggregate maximum of \(repeatedSize) input bytes") == true,
            "The same resource supplied for two locales is charged twice")
        try check("mapping-no-discovery-charge", try LocalizedStringLoader.loadFromResources([en: repeated, fr: repeated],
            loadingOptions: .init(maximumDiscoveryEntries: 1)).count == 2, "Explicit maps do not enumerate or charge directory entries")
        let missing = root.appendingPathComponent("missing")
        let capped = try refused { _ = try LocalizedStringLoader.loadFromResources([en: missing, fr: URL(string: "https://example.invalid/catalog")!],
            loadingOptions: .init(maximumLocalizedStringsFiles: 1)) }
        try check("mapping-file-cap-before-validation-and-io", (capped as? LocalizedStringLoadingError)?.message.hasPrefix("Resource mapping contains 2") == true,
            "Complete map count is refused before URL validation or missing-file I/O")
        let directoryError = try refused { _ = try LocalizedStringLoader.loadFromResources([en: firstDir]) }
        try check("mapping-directory-refused", (directoryError as? LocalizedStringLoadingError)?.message.hasSuffix("is not a regular file") == true,
            "Native explicit mapping refuses directory streams")
        let collision = try refused { _ = try LocalizedStringLoader.loadFromResources([
            LocaleTag.forLanguageTag("und"): missing, LocaleTag.forLanguageTag("UND"): missing]) }
        try check("mapping-rendered-collision-before-io", (collision as? LocalizedStringLoadingError)?.kind == .duplicateLocale,
            "Distinct typed identities rendering und collide before either missing file is opened")
        let nested = try directory("nested", under: firstDir)
        _ = try write("invalid JSON", "not-a-locale.json", under: nested)
        try check("bundle-discovery-nonrecursive", try LocalizedStringLoader.loadFromBundle(first).count == 1,
            "Faulty nested catalog is not descended into")
        let warningText = #"{"A":{"translation":"{{n}}","placeholders":{"n":{"value":"count","translations":{"CARDINALITY_ONE":"one"}}}}}"#
        let warningFile = try write(warningText, "warning", under: root)
        let marker = BoundaryMarkerError()
        let callback = try refused { _ = try LocalizedStringLoader.loadFromResources([en: warningFile], warningHandler: { _ in
            _ = try LocalizedStringLoader.parse("{}", locale: "en"); throw marker
        }) }
        try check("warning-error-identity-and-reentry", (callback as? BoundaryMarkerError) === marker,
            "Warning handler reenters and its original error propagates unchanged")
        let ordered = try directory("ordered", under: root)
        // Reverse creation order independently of the native byte-sort order.
        _ = try write("{}", "zz.json", under: ordered); _ = try write("{}", "notes.json", under: ordered)
        let invalid = try refused { _ = try LocalizedStringLoader.loadFromDirectory(ordered) }
        try check("directory-invalid-filename-byte-order", (invalid as? LocalizedStringLoadingError)?.message.hasPrefix("File 'notes.json'") == true,
            "notes.json precedes zz.json after complete bounded discovery")
        try FileManager.default.removeItem(at: ordered); _ = try directory("ordered", under: root)
        _ = try write("{}", "fr", under: ordered); _ = try write("{}", "en", under: ordered)
        let fileCap = try refused { _ = try LocalizedStringLoader.loadFromDirectory(ordered,
            loadingOptions: .init(maximumLocalizedStringsFiles: 1)) }
        try check("directory-file-cap-byte-order", (fileCap as? StringsParseError)?.source.hasSuffix("/fr") == true,
            "Sorted en is admitted; fr names the second-file cap overflow")
        try FileManager.default.removeItem(at: ordered); _ = try directory("ordered", under: root)
        _ = try write("broken JSON", "en.json", under: ordered); _ = try write("{}", "en", under: ordered)
        let duplicate = try refused { _ = try LocalizedStringLoader.loadFromDirectory(ordered) }
        try check("directory-extensionless-before-json", (duplicate as? LocalizedStringLoadingError)?.kind == .duplicateLocale
            && (duplicate as? LocalizedStringLoadingError)?.source.hasSuffix("/en.json") == true,
            "en.json names the duplicate before its malformed contents are read")
        let discovery = try refused { _ = try LocalizedStringLoader.loadFromDirectory(ordered,
            loadingOptions: .init(maximumDiscoveryEntries: 1)) }
        try check("discovery-overflow-before-selected-file-fault", (discovery as? StringsParseError)?.message.hasSuffix("aggregate maximum of 1 discovery entries") == true,
            "Enumeration overflow wins over the duplicate/malformed selected file")
        return Report(passed: passed.sorted(), observations: observations)
    }
}

private final class BoundaryMarkerError: Error, Sendable {}
