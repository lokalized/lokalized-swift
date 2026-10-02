import Foundation
import Lokalized

enum ManifestIdentityQualification {
    static func runNative() throws -> Int {
        var checks = 0
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw ConformanceError("Manifest identity qualification: " + message) }
            checks += 1
        }
        try require(CatalogIdentityCanonicalizer.digest(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "SHA-256 empty known answer")
        try require(CatalogIdentityCanonicalizer.digest(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 abc known answer")
        let a = String(repeating: "a", count: 64), b = String(repeating: "b", count: 64)
        let input = CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en",
            localeToSha256: ["fr": b, "en": a], tiebreakerLocalesByLanguageCode: ["en": ["en", "en-GB"]])
        let expected = "{\"catalogVersion\":\"v1\",\"formatVersion\":1,\"localeToSha256\":{\"en\":\"" + a
            + "\",\"fr\":\"" + b + "\"},\"resolvedFallbackLocale\":\"en\",\"tiebreakerLocalesByLanguageCode\":{\"en\":[\"en\",\"en-GB\"]}}"
        let bytes = try LocalizedStringLoader.catalogIdentityBytes(input)
        try require(bytes == Data(expected.utf8), "exact hand-authored canonical projection")
        try require(bytes.first == 123 && bytes.last == 125, "no BOM or trailing newline")
        let identity = try LocalizedStringLoader.computeCatalogIdentity(input)
        try require(identity.catalogVersion == "v1" && identity.catalogFingerprint.utf8.count == 64, "full identity fields")
        let reordered = CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en",
            localeToSha256: ["en": a, "fr": b], tiebreakerLocalesByLanguageCode: ["en": ["en", "en-GB"]])
        try require(try LocalizedStringLoader.catalogIdentityBytes(reordered) == bytes, "property insertion order does not affect identity")
        for altered in [
            CatalogIdentityInputV1(catalogVersion: "v2", resolvedFallbackLocale: "en", localeToSha256: input.localeToSha256, tiebreakerLocalesByLanguageCode: input.tiebreakerLocalesByLanguageCode),
            CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "fr", localeToSha256: input.localeToSha256, tiebreakerLocalesByLanguageCode: input.tiebreakerLocalesByLanguageCode),
            CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en", localeToSha256: ["en": b, "fr": b], tiebreakerLocalesByLanguageCode: input.tiebreakerLocalesByLanguageCode),
            CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en", localeToSha256: input.localeToSha256, tiebreakerLocalesByLanguageCode: ["en": ["en-GB", "en"]])
        ] {
            try require(try LocalizedStringLoader.computeCatalogIdentity(altered) != identity, "each included field changes the digest")
        }
        let exactMap: [ExactString: String] = ["é": a, "e\u{301}": b, "\u{10000}": a, "\u{E000}": b, "__proto__": a]
        let unicode = try LocalizedStringLoader.catalogIdentityBytes(.init(catalogVersion: "é", resolvedFallbackLocale: "en", localeToSha256: exactMap))
        let unicodeExpected = "{\"catalogVersion\":\"é\",\"formatVersion\":1,\"localeToSha256\":{\"__proto__\":\"" + a
            + "\",\"e\u{301}\":\"" + b + "\",\"é\":\"" + a + "\",\"\u{10000}\":\"" + a
            + "\",\"\u{E000}\":\"" + b + "\"},\"resolvedFallbackLocale\":\"en\",\"tiebreakerLocalesByLanguageCode\":{}}"
        try require(unicode == Data(unicodeExpected.utf8), "UTF-16 order, exact NFC/NFD and ordinary __proto__ member")
        let nfd = try LocalizedStringLoader.computeCatalogIdentity(.init(catalogVersion: "e\u{301}", resolvedFallbackLocale: "en", localeToSha256: exactMap))
        let nfc = try LocalizedStringLoader.computeCatalogIdentity(.init(catalogVersion: "é", resolvedFallbackLocale: "en", localeToSha256: exactMap))
        try require(nfc != nfd, "catalog version is not normalized")
        try require(Set([CatalogIdentity(catalogVersion: "é", catalogFingerprint: a), CatalogIdentity(catalogVersion: "e\u{301}", catalogFingerprint: a)]).count == 2, "identity equality/hash retains exact version text")
        let escape = "\u{0}\u{1}\u{8}\u{9}\u{A}\u{C}\u{D}\"\\/\u{2028}\u{2029}"
        try require(CatalogIdentityCanonicalizer.quote(escape) == "\"\\u0000\\u0001\\b\\t\\n\\f\\r\\\"\\\\/\u{2028}\u{2029}\"", "minimal escapes and literal line separators")
        for invalid in [
            CatalogIdentityInputV1(formatVersion: 2, catalogVersion: "", resolvedFallbackLocale: ""),
            CatalogIdentityInputV1(catalogVersion: "", resolvedFallbackLocale: "en"),
            CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: ""),
            CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en", localeToSha256: ["en": String(repeating: "A", count: 64)]),
            CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en", localeToSha256: ["en": "a"])
        ] {
            do { _ = try LocalizedStringLoader.computeCatalogIdentity(invalid); throw ConformanceError("Invalid identity accepted") }
            catch let error as ConfigurationError { try require(error.kind == .invalidArgument, "typed identity refusal category") }
        }
        return checks
    }
}
