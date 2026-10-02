import CryptoKit
import Foundation
import Lokalized

let loaded = try LocalizedStringLoader.loadFromBundle(.module)
let en = try LocaleTag("en"), fr = try LocaleTag("fr")
precondition(Set(loaded.keys) == [en, fr])
precondition(loaded[en]?.sources.first?.hasSuffix("/Lokalized/en") == true)
precondition(loaded[fr]?.sources.first?.hasSuffix("/Lokalized/fr.JSON") == true)
let catalogs = loaded.mapValues { LocalizedCatalog(strings: $0.strings) }
let strings = try DefaultStrings(configuration: StringsConfiguration(
    localizedStringSupplier: { catalogs }, localeSupplier: { _ in en }, fallbackLocale: en))
let english = try strings.get("welcome", placeholders: ["name": .text("Ada")])
let french = try strings.get("welcome", placeholders: ["name": .text("Ada")], options: .forLocale(fr))
precondition(english == "Hello, Ada!" && french == "Bonjour, Ada !")
let exactKeys = try strings.getKeysForLocale(en)
precondition(exactKeys.contains("é") && exactKeys.contains("e\u{0301}"))
let items = try strings.get("items", placeholders: ["count": .integer(2)])
precondition(items == "2 items")
let explicit = try LocalizedStringLoader.loadFromBundle(.module,
    resourcePathsByLocale: [en: "Lokalized/en", fr: "Lokalized/fr.JSON"])
precondition(explicit[en]?.strings == loaded[en]?.strings && explicit[fr]?.strings == loaded[fr]?.strings)
let preferred = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["fr-CA", "en"], using: strings)
precondition(preferred.localeTag == fr)
let malformedFirst = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["invalid_tag", "en"], using: strings)
precondition(malformedFirst.localeTag == en)
let bundleFiles: [ExactString: StringsManifestFile] = try Dictionary(uniqueKeysWithValues:
    [("en", "en"), ("fr", "fr.JSON")].map { locale, name in
        let url = Bundle.module.resourceURL!.appendingPathComponent("Lokalized").appendingPathComponent(name)
        let bytes = try Data(contentsOf: url)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return (ExactString(locale), StringsManifestFile(url: name, sha256: digest, decodedBytes: bytes.count))
    })
let bundleIdentity = try LocalizedStringLoader.computeCatalogIdentity(.init(
    catalogVersion: "bundled-v1", resolvedFallbackLocale: "en", localeToSha256: bundleFiles.mapValues(\.sha256)))
let bundleManifest = StringsManifestV1(catalogVersion: bundleIdentity.catalogVersion,
    catalogFingerprint: bundleIdentity.catalogFingerprint, fallbackLocale: "en",
    baseUrl: Bundle.module.resourceURL!.appendingPathComponent("Lokalized", isDirectory: true).absoluteString,
    files: bundleFiles)
let bundlePlan = try LocalizedStringLoader.fetchSet(bundleManifest, lookupLocale: "fr-CA")
precondition(bundlePlan.map(\.locale) == ["fr", "en"])
precondition(bundlePlan.allSatisfy { $0.url.hasPrefix("file:") && $0.expectedDecodedBytes != nil })
print("SwiftPM Bundle.module catalogs passed")
