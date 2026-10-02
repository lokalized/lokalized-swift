import Foundation
import Darwin
import CryptoKit
import Lokalized

struct Observation: Encodable {
    let workload: String
    let iterations: Int
    let inputBytes: Int
    let inputSHA256: String
    let checksum: Int
    let durationNs: [String: UInt64]
    let liveMallocDeltaBytes: [String: Int64]
    let peakResidentBytes: Int64
    let budgetRefusalChecked: Bool
}
func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func heap() -> UInt64 {
    var stats = malloc_statistics_t()
    malloc_zone_statistics(nil, &stats)
    return UInt64(stats.size_in_use)
}
func peakRSS() -> Int64 {
    var usage = rusage()
    precondition(getrusage(RUSAGE_SELF, &usage) == 0)
    return Int64(usage.ru_maxrss) // Darwin reports bytes.
}
func runtime(_ catalogs: [LocaleTag: LocalizedCatalog], _ locale: LocaleTag,
             limits: TranslationRuntimeLimits = .defaults) throws -> DefaultStrings {
    try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { catalogs },
        localeSupplier: { _ in locale }, fallbackLocale: locale, runtimeLimits: limits, bidiIsolation: .disabled))
}
func measured(_ mode: String) throws -> Observation {
    _ = now(); _ = heap() // Warm measurement helpers, not library tables.
    var durations: [String: UInt64] = [:], deltas: [String: Int64] = [:]
    var iterations = 1, checksum = 0, refusalChecked = false
    var measuredPeak: Int64?
    var input = Data()
    func finish() -> Observation {
        let resident = measuredPeak ?? peakRSS() // Before hashing and JSON report formatting.
        return Observation(workload: mode, iterations: iterations, inputBytes: input.count,
            inputSHA256: SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined(),
            checksum: checksum, durationNs: durations, liveMallocDeltaBytes: deltas,
            peakResidentBytes: resident, budgetRefusalChecked: refusalChecked)
    }
    if mode == "cold-start" {
        input = Data(#"{"hello":"Hello {{name}}!"}"#.utf8)
        let before = heap(), start = now()
        let en = try LocaleTag("en")
        let tagged = now()
        let parsed = try LocalizedStringLoader.parse(input, locale: "en")
        let parsedAt = now()
        let strings = try runtime([en: LocalizedCatalog(strings: parsed.strings)], en)
        let constructed = now()
        let result = try strings.getResult("hello", placeholders: ["name": .text("Ada")])
        let ended = now(), after = heap()
        precondition(result.translation == "Hello Ada!" && result.status == .translated)
        checksum = result.translation.utf16.count
        durations = ["total": ended-start, "localeFirstUse": tagged-start, "parse": parsedAt-tagged,
                     "construct": constructed-parsedAt, "firstLookup": ended-constructed]
        deltas["total"] = Int64(after)-Int64(before)
        return withExtendedLifetime((parsed, strings)) { finish() }
    }
    let en = try LocaleTag("en")
    if mode == "catalog-1000" || mode == "catalog-10000" {
        let count = mode == "catalog-1000" ? 1_000 : 10_000
        input = Data(("{" + (0..<count).map { "\"K\($0)\":\"Value\($0) {{name}}\"" }.joined(separator: ",") + "}").utf8)
        let before = heap(), start = now()
        let parsed = try LocalizedStringLoader.parse(input, locale: "en")
        let parsedAt = now(), parseHeap = heap()
        let constructStart = now()
        let strings = try runtime([en: LocalizedCatalog(strings: parsed.strings)], en)
        let constructed = now(), constructedHeap = heap()
        let lookupStart = now()
        let result = try strings.getResult(ExactString("K\(count-1)"), placeholders: ["name": .text("Ada")])
        let ended = now()
        precondition(parsed.strings.count == count && result.translation == "Value\(count-1) Ada" && result.status == .translated)
        checksum = parsed.strings.count
        durations = ["parse": parsedAt-start, "construct": constructed-constructStart, "firstLookup": ended-lookupStart]
        deltas = ["parse": Int64(parseHeap)-Int64(before), "construct": Int64(constructedHeap)-Int64(parseHeap)]
        return withExtendedLifetime((parsed, strings)) { finish() }
    }
    if mode == "idna-manifest" {
        let digest = String(repeating: "a", count: 64)
        let identity = try LocalizedStringLoader.computeCatalogIdentity(.init(catalogVersion: "benchmark-v1",
            resolvedFallbackLocale: "en", localeToSha256: ["en": digest]))
        let manifest = StringsManifestV1(catalogVersion: identity.catalogVersion, catalogFingerprint: identity.catalogFingerprint,
            fallbackLocale: "en", baseUrl: "https://bücher.example/catalogs/", files: ["en": .init(url: "en.json", sha256: digest)])
        input = Data(manifest.baseUrl.utf8)
        let before = heap(), start = now()
        let planned = try LocalizedStringLoader.fetchSet(manifest, lookupLocale: "en")
        let first = now(), initializedHeap = heap()
        let canonicalURL = "https://xn--bcher-kva.example/catalogs/en.json"
        precondition(planned.count == 1 && planned[0].url == canonicalURL)
        iterations = 200
        let repeatedStart = now()
        for _ in 0..<iterations {
            let result = try LocalizedStringLoader.fetchSet(manifest, lookupLocale: "en")
            precondition(result.count == 1 && result[0].url == canonicalURL)
            checksum += result[0].url.utf16.count
        }
        let ended = now(), after = heap()
        durations = ["firstUse": first-start, "repeated": ended-repeatedStart]
        deltas = ["firstUse": Int64(initializedHeap)-Int64(before), "repeated": Int64(after)-Int64(initializedHeap)]
        return withExtendedLifetime(planned) { finish() }
    }
    let plural = #"{"items":{"translation":"{{n}}","placeholders":{"n":{"value":"count","translations":{"CARDINALITY_ONE":"one","CARDINALITY_OTHER":"other"}}}}}"#
    var key: ExactString = "hello", expected = "Hello Ada!", values: PlaceholderValues = ["name": .text("Ada")]
    var options = TranslationOptions.none
    if mode == "lookup-plain" || mode == "lookup-fallback" {
        input = Data(#"{"hello":"Hello {{name}}!"}"#.utf8)
        iterations = mode == "lookup-plain" ? 20_000 : 10_000
    } else if mode == "plural-integer" || mode == "plural-double" || mode == "plural-double-pi" || mode == "plural-double-max" || mode == "plural-decimal" {
        input = Data(plural.utf8); key = "items"
        if mode == "plural-integer" { values = ["count": .number(.integer(1))]; expected = "one"; iterations = 10_000 }
        if mode == "plural-double" { values = ["count": .number(.double(0.1))]; expected = "other"; iterations = 2_000 }
        if mode == "plural-double-pi" { values = ["count": .number(.double(.pi))]; expected = "other"; iterations = 2_000 }
        if mode == "plural-double-max" { values = ["count": .number(.double(.greatestFiniteMagnitude))]; expected = "other"; iterations = 1_000 }
        if mode == "plural-decimal" { values = ["count": .number(try .forDecimal("1.00"))]; expected = "other"; iterations = 10_000 }
    } else if mode == "generated-32768" {
        let template = String(repeating: "{{leaf}}", count: 256)
        let leaf = String(repeating: "v", count: 128)
        input = Data("{\"k\":{\"translation\":\"\(template)\",\"placeholders\":{\"leaf\":{\"translation\":\"\(leaf)\"}}}}".utf8)
        key = "k"; expected = String(repeating: "v", count: 32_768); values = [:]; iterations = 100
    } else { throw NSError(domain: "unknown benchmark workload", code: 1) }
    let parsed = try LocalizedStringLoader.parse(input, locale: "en")
    var catalogs = [en: LocalizedCatalog(strings: parsed.strings)]
    if mode == "lookup-fallback" {
        let fr = try LocaleTag("fr")
        catalogs[fr] = LocalizedCatalog(strings: try LocalizedStringLoader.parse(#"{"other":"autre"}"#, locale: "fr").strings)
        options = try .forLocale(fr)
    }
    let strings = try runtime(catalogs, en)
    for _ in 0..<20 {
        let result = try strings.getResult(key, placeholders: values, options: options)
        precondition(result.translation == expected && result.status == .translated)
    }
    let before = heap(), start = now()
    for _ in 0..<iterations {
        let result = try strings.getResult(key, placeholders: values, options: options)
        precondition(result.translation == expected && result.status == .translated && result.resolvedLocale == en)
        if mode == "lookup-fallback" { precondition(result.isFallback && result.attemptedLocales.count == 2) }
        checksum += result.translation.utf16.count
    }
    let ended = now(), after = heap()
    durations["repeated"] = ended-start; deltas["repeated"] = Int64(after)-Int64(before)
    measuredPeak = peakRSS()
    if mode == "generated-32768" {
        let limited = try runtime(catalogs, en, limits: .init(maximumInterpolatedOutputCharacters: 32_767))
        let refused = try limited.getResult(key)
        precondition(refused.status == .returnedKey && refused.failureReason == .resolutionFailure && refused.cause != nil)
        refusalChecked = true
    }
    return withExtendedLifetime((parsed, strings)) { finish() }
}
let result = try measured(CommandLine.arguments[1])
let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(result)); print("")
