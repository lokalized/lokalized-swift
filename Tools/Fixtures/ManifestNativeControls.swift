import Foundation
import Lokalized

struct ControlFailure: Error { let id: String }
func controls() throws -> [String] {
    var passed: [String] = []
    func check(_ id: String, _ condition: Bool) throws {
        guard condition else { throw ControlFailure(id: id) }
        passed.append(id)
    }
    func refused(_ body: () throws -> Void) -> (any Error)? {
        do { try body(); return nil } catch { return error }
    }
    let digest = String(repeating: "a", count: 64)
    let implied = CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en")
    let explicit = CatalogIdentityInputV1(formatVersion: 1, catalogVersion: "v1", resolvedFallbackLocale: "en")
    try check("identity-default-format-version", implied.formatVersion == 1
        && LocalizedStringLoader.catalogIdentityBytes(implied) == LocalizedStringLoader.catalogIdentityBytes(explicit)
        && LocalizedStringLoader.computeCatalogIdentity(implied) == LocalizedStringLoader.computeCatalogIdentity(explicit))
    try check("identity-optional-empty-maps", implied.localeToSha256.isEmpty && implied.tiebreakerLocalesByLanguageCode.isEmpty)
    let bad = CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en", localeToSha256: ["en": "short"])
    let digestError = refused { _ = try LocalizedStringLoader.computeCatalogIdentity(bad) } as? ConfigurationError
    try check("identity-malformed-digest-runtime-refusal", digestError?.kind == .invalidArgument && digestError?.cause == nil)
    try check("manifest-raw-null-runtime-refusal", refused { _ = try LocalizedStringLoader.parseStringsManifest("null") } is ConfigurationError)
    try check("manifest-semantic-null-runtime-refusal", refused { _ = try LocalizedStringLoader.validateStringsManifest(StringsManifestValue.null) } is ConfigurationError)
    for (id, units, escape) in [
        ("high", [UInt16(0xD800)], #"\uD800"#), ("low", [UInt16(0xDFFF)], #"\uDFFF"#)
    ] {
        // The repairing Swift initializer cannot supply the original JS carrier.
        let repaired = String(decoding: units, as: UTF16.self)
        try check("unicode-decoder-" + id + "-repairs", Array(repaired.utf16) == [0xFFFD]
            && ExactString(repaired) == ExactString("\u{FFFD}"))
        let document = #"{"extra":""# + escape + #""}"#
        let error = refused { _ = try LocalizedStringLoader.parseStringsManifest(document, source: "surrogate.json") } as? StringsParseError
        try check("manifest-escaped-" + id + "-surrogate-refusal", error?.source == "surrogate.json" && error?.cause != nil)
    }
    let replacement = CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en", localeToSha256: ["\u{FFFD}": digest])
    let replacementBytes = try LocalizedStringLoader.catalogIdentityBytes(replacement)
    try check("identity-valid-replacement-character-keys", String(decoding: replacementBytes, as: UTF8.self).contains("\u{FFFD}"))
    let supplementary = CatalogIdentityInputV1(catalogVersion: "😀", resolvedFallbackLocale: "en", localeToSha256: ["😀": digest])
    try check("identity-valid-supplementary-text", String(decoding: LocalizedStringLoader.catalogIdentityBytes(supplementary), as: UTF8.self).contains("😀"))
    let input = CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en", localeToSha256: ["en": digest, "fr": digest])
    let identity = try LocalizedStringLoader.computeCatalogIdentity(input)
    let manifest = StringsManifestV1(catalogVersion: "v1", catalogFingerprint: identity.catalogFingerprint,
        fallbackLocale: "en", baseUrl: "https://cdn.example/v1/",
        files: ["en": .init(url: "en.json", sha256: digest), "fr": .init(url: "fr.json", sha256: digest)])
    let options = try LocalizedStringLoadingOptions(maximumLocalizedStringsFiles: 2)
    try check("manifest-options-accepted", LocalizedStringLoader.validateStringsManifest(manifest, loadingOptions: options).files.count == 2)
    let small = try LocalizedStringLoadingOptions(maximumLocalizedStringsFiles: 1)
    try check("manifest-limit-runtime-refusal", refused { _ = try LocalizedStringLoader.validateStringsManifest(manifest, loadingOptions: small) } is ConfigurationError)
    try check("manifest-planning-empty-string-runtime-refusal", refused { _ = try LocalizedStringLoader.chain(manifest, lookupLocale: "") } is LocaleTagError)
    try check("manifest-planning-chain", LocalizedStringLoader.chain(manifest, lookupLocale: "fr-CA") == ["fr-CA", "fr", "en"])
    let files = try LocalizedStringLoader.fetchSet(manifest, lookupLocale: "fr-CA")
    try check("manifest-planning-fetch-set", files.map(\.locale) == ["fr", "en"] && files.map(\.url) == ["https://cdn.example/v1/fr.json", "https://cdn.example/v1/en.json"])
    return passed.sorted()
}
let data = try JSONSerialization.data(withJSONObject: ["passed": controls()], options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
