import Foundation
import XCTest
@testable import Lokalized

final class BundleCatalogLoaderTests: XCTestCase {
    private func withBundle(_ body: (Bundle, URL) throws -> Void) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = parent.appendingPathComponent("Catalogs.bundle", isDirectory: true)
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let info: [String: Any] = ["CFBundleIdentifier": "com.lokalized.tests.\(UUID().uuidString)",
                                   "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: root))
        try body(bundle, resources)
    }

    func testExplicitBundleEnumeratesAllCatalogsAndPreservesOrigins() throws {
        try withBundle { bundle, root in
            let directory = root.appendingPathComponent("Lokalized", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(#"{"hello":"Hello {{name}}","é":"NFC","e\u0301":"NFD"}"#.utf8).write(to: directory.appendingPathComponent("en"))
            try Data(#"{"hello":"Bonjour {{name}}"}"#.utf8).write(to: directory.appendingPathComponent("fr.JSON"))
            let loaded = try LocalizedStringLoader.loadFromBundle(bundle)
            let en = try LocaleTag("en"), fr = try LocaleTag("fr")
            XCTAssertEqual(Set(loaded.keys), [en, fr])
            let english = try XCTUnwrap(loaded[en])
            XCTAssertEqual(english.strings.count, 3)
            XCTAssertTrue(english.sources[0].hasSuffix("/Lokalized/en"))
            XCTAssertEqual(english.originsByKey["hello"], english.sources)
            let catalogs = loaded.mapValues { LocalizedCatalog(strings: $0.strings) }
            let strings = try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { catalogs },
                localeSupplier: { _ in en }, fallbackLocale: en))
            XCTAssertEqual(try strings.get("hello", placeholders: ["name": .text("Ada")]), "Hello Ada")
            XCTAssertEqual(try strings.get("hello", placeholders: ["name": .text("Ada")], options: .forLocale(fr)), "Bonjour Ada")
            XCTAssertEqual(try strings.getKeysForLocale(en), ["hello", "é", "e\u{0301}"])
        }
    }

    func testExactMappedPathsDoNotApplyAppleLocalizationSelection() throws {
        try withBundle { bundle, root in
            let nested = root.appendingPathComponent("Payloads/en.lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data(#"{"key":"explicit language"}"#.utf8).write(to: nested.appendingPathComponent("arbitrary.catalog"))
            let fr = try LocaleTag("fr")
            let loaded = try LocalizedStringLoader.loadFromBundle(bundle,
                resourcePathsByLocale: [fr: "Payloads/en.lproj/arbitrary.catalog"])
            XCTAssertEqual(loaded[fr]?.locale, "fr")
            XCTAssertEqual(loaded[fr]?.strings.first?.translation, "explicit language")
            XCTAssertTrue(loaded[fr]?.sources.first?.hasSuffix("/Payloads/en.lproj/arbitrary.catalog") == true)
        }
    }

    func testMissingRequestedBundleDirectoryThrowsNamedLoadingError() throws {
        try withBundle { bundle, _ in
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromBundle(bundle, directory: "Absent")) {
                XCTAssertTrue($0 is LocalizedStringLoadingError)
                XCTAssertTrue(String(describing: $0).contains("Absent"))
            }
        }
    }

    func testAllMappedPathsAreValidatedBeforeCatalogReads() throws {
        try withBundle { bundle, root in
            try Data("not JSON".utf8).write(to: root.appendingPathComponent("broken"))
            let en = try LocaleTag("en"), fr = try LocaleTag("fr")
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromBundle(bundle,
                resourcePathsByLocale: [en: "broken", fr: "../outside"])) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.kind, .invalidResource)
                XCTAssertTrue(String(describing: $0).contains("relative path"))
            }
        }
    }

    func testScalarPathSeparatorsPreserveCombiningMarks() throws {
        try withBundle { bundle, root in
            let path = "Lokalized/\u{0301}nested"
            let directory = root.appendingPathComponent("Lokalized").appendingPathComponent("\u{0301}nested")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: directory.appendingPathComponent("en"))
            let loaded = try LocalizedStringLoader.loadFromBundle(bundle, directory: path)
            XCTAssertEqual(loaded.count, 1)
            XCTAssertThrowsError(try LocalizedStringLoader.loadFromBundle(bundle, directory: "Lokalized/\u{0301}" + "/../outside")) {
                XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.kind, .invalidResource)
            }
        }
    }

    func testLiteralPathValidationAndNonrecursiveBundleLoading() throws {
        try withBundle { bundle, root in
            for path in ["", "/Lokalized", "Lokalized/", "Lokalized//nested", ".", "../Lokalized", "Lokalized\\nested", "Lokalized\u{0}"] {
                XCTAssertThrowsError(try LocalizedStringLoader.loadFromBundle(bundle, directory: path)) {
                    XCTAssertEqual(($0 as? LocalizedStringLoadingError)?.kind, .invalidResource)
                }
            }
            let directory = root.appendingPathComponent("Lokalized", isDirectory: true)
            let child = directory.appendingPathComponent("nested", isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: child.appendingPathComponent("not-a-locale.json"))
            try Data("{}".utf8).write(to: directory.appendingPathComponent(".\u{0301}bad.json"))
            try Data("{}".utf8).write(to: directory.appendingPathComponent("en"))
            let loaded = try LocalizedStringLoader.loadFromBundle(bundle)
            XCTAssertEqual(loaded.count, 1)
        }
    }
}
