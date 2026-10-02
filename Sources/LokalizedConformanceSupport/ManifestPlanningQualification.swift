import Foundation
import Lokalized

public extension ConformanceRunner {
    /// Public planning probes: coverage, ordering, canonical election, file
    /// projection and refusal precedence, independent of donor expectations.
    static func manifestPlanningSelfTest() throws -> Int {
        var checks = 0
        func expect(_ value: @autoclosure () throws -> Bool, _ detail: String) throws {
            checks += 1
            guard try value() else { throw ConformanceError("Manifest planning self-test: \(detail)") }
        }
        func refusal(_ body: () throws -> Void) throws -> any Error {
            checks += 1
            do { try body() } catch { return error }
            throw ConformanceError("Expected manifest planning refusal")
        }
        let a = String(repeating: "a", count: 64), b = String(repeating: "b", count: 64)
        func built(_ files: [ExactString: StringsManifestFile], fallback: String = "en", ties: [ExactString: [String]] = [:],
            base: String = "https://EXAMPLE.com:443/v1/") throws -> StringsManifestV1 {
            let provisional = StringsManifestV1(catalogVersion: "v1", catalogFingerprint: a, fallbackLocale: fallback,
                baseUrl: base, files: files, tiebreakerLocalesByLanguageCode: ties)
            let identity = try LocalizedStringLoader.computeCatalogIdentity(LocalizedStringLoader.catalogIdentityInputFor(provisional))
            return StringsManifestV1(catalogVersion: "v1", catalogFingerprint: identity.catalogFingerprint, fallbackLocale: fallback,
                baseUrl: base, files: files, tiebreakerLocalesByLanguageCode: ties)
        }
        let base = try built(["en": .init(url: "en.json", sha256: a), "fr": .init(url: "../shared.json?x=1#f", sha256: b, decodedBytes: 0)])
        let config = try LocalizedStringLoader.localeConfigurationForManifest(base)
        try expect(config.supportedLocales == ["en", "fr"], "full manifest exact tag order")
        try expect(config.fallbackLocale == "en" && config.tiebreakerLocalesByLanguageCode.isEmpty, "fallback and explicit ties preserved")
        let chain = try LocalizedStringLoader.chain(base, lookupLocale: "fr-CA")
        try expect(chain == ["fr-CA", "fr", "en"], "unbacked ancestors retained")
        let fetch = try LocalizedStringLoader.fetchSet(base, lookupLocale: "fr-CA")
        try expect(fetch.map(\.locale) == ["fr", "en"], "fetch selection omits absent candidates")
        try expect(fetch.map(\.url) == ["https://example.com/shared.json?x=1#f", "https://example.com/v1/en.json"], "resolved absolute URL spelling")
        try expect(fetch.map(\.sha256) == [b, a], "digest stays with selected file")
        try expect(fetch[0].expectedDecodedBytes == 0 && fetch[1].expectedDecodedBytes == nil, "zero and missing byte declarations distinct")
        let whole = try LocalizedStringLoader.wholeManifestPlan(base)
        try expect(whole.map(\.locale) == ["en", "fr"], "whole plan exact tag order")
        try expect(whole[1].url == fetch[0].url, "whole and subset URL projection agree")
        try expect(try LocalizedStringLoader.chain(base, lookupLocale: "zz-AA") == ["zz-AA", "zz", "en"], "unknown valid lookup accepted")
        try expect(try LocalizedStringLoader.chain(base, lookupLocale: "FR-ca") == chain, "lookup subtag casing")
        try expect(try LocalizedStringLoader.chain(base, lookupLocale: "x-private") == ["x-private", "und", "en"], "private lookup remains observable")
        try expect(try LocalizedStringLoader.chain(base, lookupLocale: "en-x-lvariant-NY").first == "en-x-lvariant-NY", "syntactic lookup does not impose native Builder reconstruction")
        let aliases = try built(["mo": .init(url: "mo", sha256: a), "en": .init(url: "en", sha256: b)], fallback: "ro")
        try expect(try LocalizedStringLoader.localeConfigurationForManifest(aliases).fallbackLocale == "mo", "configured CLDR alias elects authored tag")
        try expect(try LocalizedStringLoader.chain(aliases, lookupLocale: "ro") == ["mo"], "post-election locale dedup")
        let variants = try built(["en-FONIPA": .init(url: "one", sha256: a), "en-fonipa": .init(url: "two", sha256: b)],
            fallback: "en-FONIPA", ties: ["en": ["en-FONIPA", "en-fonipa"]])
        try expect(try LocalizedStringLoader.chain(variants, lookupLocale: "en-FONIPA") == ["en-FONIPA", "en", "en-fonipa"], "case-distinct authored variants retained")
        try expect(try LocalizedStringLoader.fetchSet(variants, lookupLocale: "en-FONIPA").map(\.locale) == ["en-FONIPA", "en-fonipa"], "native matcher restrictions do not shrink wire keys")
        let shared = try built(["en": .init(url: "same.json", sha256: a), "fr": .init(url: "same.json", sha256: a)])
        let sharedFetch = try LocalizedStringLoader.fetchSet(shared, lookupLocale: "fr")
        try expect(sharedFetch.count == 2 && sharedFetch[0].url == sharedFetch[1].url, "shared URLs do not collapse distinct locales")
        let language = try built(["en-GB": .init(url: "gb", sha256: a), "en-US": .init(url: "us", sha256: b)],
            fallback: "en-GB", ties: ["en": ["en-US", "en-GB"]])
        try expect(try LocalizedStringLoader.chain(language, lookupLocale: "en-AU") == ["en-AU", "en-001", "en", "en-US", "en-GB"], "authored compatible-script tie order")
        try expect(try LocalizedStringLoader.localeConfigurationForManifest(language).tiebreakerLocalesByLanguageCode == ["en": ["en-US", "en-GB"]], "no synthesized tie pollution")
        let file = try built(["en": .init(url: "../en.json", sha256: a)], base: "file:///srv/catalogs/v1/")
        try expect(try LocalizedStringLoader.fetchSet(file, lookupLocale: "en")[0].url == "file:///srv/catalogs/en.json", "file URL projection")
        let missingSlash = try built(["en": .init(url: "en.json", sha256: a)], base: "https://cdn.example/v1")
        try expect(try LocalizedStringLoader.fetchSet(missingSlash, lookupLocale: "en")[0].url == "https://cdn.example/en.json", "base final segment replacement")
        let absolute = try built(["en": .init(url: "https://other.example/x/../en?x=1", sha256: a)])
        try expect(try LocalizedStringLoader.fetchSet(absolute, lookupLocale: "en")[0].url == "https://other.example/en?x=1", "absolute cross-origin entry")
        for operation in 0..<4 {
            let error = try refusal {
                let limits = try LocalizedStringLoadingOptions(maximumLocalizedStringsFiles: 1)
                switch operation {
                case 0: _ = try LocalizedStringLoader.localeConfigurationForManifest(base, loadingOptions: limits)
                case 1: _ = try LocalizedStringLoader.chain(base, lookupLocale: "!", loadingOptions: limits)
                case 2: _ = try LocalizedStringLoader.fetchSet(base, lookupLocale: "!", loadingOptions: limits)
                default: _ = try LocalizedStringLoader.wholeManifestPlan(base, loadingOptions: limits)
                }
            }
            try expect((error as? ConfigurationError)?.message == "A manifest declares 2 files, which exceeds the maximum of 1", "every public projection revalidates before lookup")
        }
        for lookup in ["", "en_US", "en-!"] {
            try expect(try refusal { _ = try LocalizedStringLoader.chain(base, lookupLocale: lookup) } is LocaleTagError, "typed invalid lookup diagnostic")
        }
        let badIdentity = StringsManifestV1(catalogVersion: "v1", catalogFingerprint: b, fallbackLocale: "en", baseUrl: base.baseUrl, files: base.files)
        try expect((try refusal { _ = try LocalizedStringLoader.fetchSet(badIdentity, lookupLocale: "!") } as? ConfigurationError)?.message.contains("declared catalogFingerprint does not match") == true,
                   "identity refusal precedes invalid lookup")
        // The pinned JS helper projects UND twice. Retain this source behavior;
        // a platform spelling must not erase its observable non-idempotence.
        try expect(try ManifestLocale.normalizeTag("UND-x-foo") == "und-x-foo", "first JDK projection")
        try expect(try ManifestLocale.normalizeTag("und-x-foo") == "x-foo", "second JDK projection remains observable")
        return checks
    }
}
