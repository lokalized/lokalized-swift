// Development-only public consumer. No XCTest, Reference artifacts or networking.
import Foundation
import Lokalized

final class Marker: Error, Sendable {}
struct ControlFailure: Error { let id: String }
final class Trace: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    private var captured: TranslationFailure?
    func append(_ text: String) { lock.withLock { storage.append(text) } }
    func failure(_ value: TranslationFailure) { lock.withLock { captured = value } }
    var entries: [String] { lock.withLock { storage } }
    var lastFailure: TranslationFailure? { lock.withLock { captured } }
}

func makeRuntime(_ bodies: [(String, String)], requested: String = "fr-CA",
    handler: TranslationFailureHandler? = nil, policy: TranslationFallbackPolicy? = nil,
    resolver: PhoneticResolver? = nil) throws -> DefaultStrings {
    var catalogs: [LocaleTag: LocalizedCatalog] = [:]
    for (tag, body) in bodies {
        catalogs[try LocaleTag(tag)] = LocalizedCatalog(strings: try LocalizedStringLoader.parse(body, locale: tag).strings)
    }
    let snapshot = catalogs
    let locale = try LocaleTag(requested)
    let ties = Dictionary(grouping: snapshot.keys, by: \.language)
        .filter { $0.value.count > 1 }.mapValues { $0.sorted { $0.tag < $1.tag } }
    return try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { snapshot },
        localeSupplier: { _ in locale }, fallbackLocale: LocaleTag("en"), tiebreakerLocalesByLanguageCode: ties,
        translationFailureHandler: handler, translationFallbackPolicy: policy, phoneticResolver: resolver))
}

func controls() throws -> [String] {
    var passed: [String] = []
    func check(_ id: String, _ condition: @autoclosure () throws -> Bool) throws {
        guard try condition() else { throw ControlFailure(id: id) }
        passed.append(id)
    }
    func thrown(_ body: () throws -> Void) -> (any Error)? {
        do { try body(); return nil } catch { return error }
    }
    let marker = Marker()
    let directTrace = Trace()
    let direct = try makeRuntime([("en", #"{"k":"v"}"#)], requested: "en",
        handler: TranslationFailureHandler { _ in directTrace.append("handler"); throw marker })
    try check("handler-unconsulted-on-success", try direct.get("k") == "v" && directTrace.entries.isEmpty)
    let singleTrace = Trace()
    let single = try makeRuntime([("en", "{}")], requested: "en",
        policy: TranslationFallbackPolicy { _, _, _ in singleTrace.append("policy"); throw marker })
    try check("policy-unconsulted-on-single-candidate", try single.get("missing") == "missing" && singleTrace.entries.isEmpty)

    let walk = Trace()
    let exhausted = try makeRuntime([("fr", "{}"), ("en", "{}")],
        handler: TranslationFailureHandler { failure in
            walk.append("handler:" + failure.attemptedLocales.map(\.tag).joined(separator: ",")); return .returnKey
        }, policy: TranslationFallbackPolicy { _, locale, _ in walk.append("policy:" + locale.tag); return true })
    _ = try exhausted.getResult("missing")
    try check("handler-after-complete-walk", walk.entries == ["policy:fr-CA", "policy:fr", "handler:fr-CA,fr,en"])

    for useResult in [false, true] {
        let trace = Trace()
        let refusal = try makeRuntime([("fr", "{}"), ("en", "{}")],
            handler: TranslationFailureHandler { _ in trace.append("handler"); throw Marker() },
            policy: TranslationFallbackPolicy { _, locale, _ in trace.append("policy:" + locale.tag); throw marker })
        let error = thrown { if useResult { _ = try refusal.getResult("missing") } else { _ = try refusal.get("missing") } }
        try check(useResult ? "policy-error-getResult" : "policy-error-get", (error as? Marker) === marker)
        try check(useResult ? "policy-before-handler-getResult" : "policy-before-handler-get", trace.entries == ["policy:fr-CA"])
    }

    let expression = #"{"k":{"alternatives":[{"noun == PHONETIC_VOWEL":"vowel"},{"noun == PHONETIC_OTHER":"other"}]}}"#
    let first = Marker(), second = Marker()
    let causeTrace = Trace()
    let causes = try makeRuntime([("fr-CA", expression), ("fr", expression), ("en", "{}")],
        handler: TranslationFailureHandler { failure in causeTrace.failure(failure); return .returnKey },
        policy: TranslationFallbackPolicy { reason, locale, cause in
            causeTrace.append("\(locale.tag):\(reason.rawValue):\((cause as? Marker) === first ? "first" : "second")"); return true
        }, resolver: { _, locale in throw locale.tag == "fr-CA" ? first : second })
    let failed = try causes.getResult("k", placeholders: ["noun": .text("apple")])
    try check("policy-receives-current-resolution-cause", causeTrace.entries == ["fr-CA:resolution-failure:first", "fr:resolution-failure:second"])
    try check("handler-retains-first-same-type-cause", (causeTrace.lastFailure?.cause as? Marker) === first)
    try check("result-retains-first-same-type-cause", (failed.cause as? Marker) === first)
    let throwing = try makeRuntime([("fr-CA", expression), ("fr", expression), ("en", "{}")],
        handler: .throwException(), policy: .fallbackOnAnyFailure(),
        resolver: { _, locale in throw locale.tag == "fr-CA" ? first : second })
    try check("get-rethrows-first-cause-verbatim", (thrown { _ = try throwing.get("k", placeholders: ["noun": .text("apple")]) } as? Marker) === first)
    let expressionRefusal = try makeRuntime([("en", expression)], requested: "en", resolver: { _, _ in throw marker })
    try check("expression-resolver-error-retains-cause", (try expressionRefusal.getResult("k", placeholders: ["noun": .text("apple")]).cause as? Marker) === marker)
    let other = try makeRuntime([("en", expression)], requested: "en", resolver: { _, _ in .other })
    try check("other-is-valid-phonetic-category", try other.get("k", placeholders: ["noun": .text("apple")]) == "other")
    let missingMapping = try makeRuntime([("en", expression)], requested: "en", resolver: { _, _ in throw marker })
    try check("unmapped-resolver-can-throw-explicitly", (try missingMapping.getResult("k", placeholders: ["noun": .text("absent")]).cause as? Marker) === marker)
    let policyCause = Trace()
    let policyResolution = try makeRuntime([("fr-CA", expression), ("en", "{}")],
        handler: TranslationFailureHandler { _ in policyCause.append("handler"); return .returnKey },
        policy: TranslationFallbackPolicy { reason, _, cause in
            policyCause.append(reason == .resolutionFailure && (cause as? Marker) === first ? "first" : "wrong"); throw marker
        }, resolver: { _, _ in throw first })
    try check("policy-error-preserves-consultation-cause", (thrown { _ = try policyResolution.get("k", placeholders: ["noun": .text("apple")]) } as? Marker) === marker && policyCause.entries == ["first"])

    let nullTrace = Trace()
    let nulls = try makeRuntime([("en", expression)], requested: "en", resolver: { _, _ in nullTrace.append("resolver"); return .vowel })
    let nullResult = try nulls.getResult("k", placeholders: ["noun": .null])
    try check("explicit-null-remains-runtime-refusal", nullResult.failureReason == .resolutionFailure && nullTrace.entries.isEmpty)
    let missingResult = try nulls.getResult("k")
    try check("missing-binding-remains-runtime-refusal", missingResult.failureReason == .resolutionFailure && nullTrace.entries.isEmpty)

    let en = try LocaleTag("en")
    let catalog = LocalizedCatalog(strings: try LocalizedStringLoader.parse(#"{"k":"v"}"#, locale: "en").strings)
    let match = try DefaultLocaleMatcher(supportedLocales: [en], fallbackLocale: en).matchFor(en)
    let fromMatch = try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { [en: catalog] },
        localeSupplier: nil, localeMatchSupplier: { _ in match }, fallbackLocale: en))
    try check("nil-locale-supplier-keeps-match-supplier", try fromMatch.getResult("k").localeMatchResult === match)
    let fromLocale = try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { [en: catalog] },
        localeSupplier: { _ in en }, localeMatchSupplier: nil, fallbackLocale: en, tiebreakerLocalesByLanguageCode: nil))
    try check("nil-match-supplier-keeps-locale-supplier", try fromLocale.get("k") == "v")
    try check("nil-whole-tiebreaker-setting-is-valid", fromLocale.supportedLocales == Set([en]))
    for (id, body) in [("raw-null-catalog-refused", "null"), ("raw-null-entry-refused", #"{"k":null}"#),
        ("raw-null-placeholder-definition-refused", #"{"k":{"translation":"{{x}}","placeholders":{"x":null}}}"#)] {
        try check(id, thrown { _ = try LocalizedStringLoader.parse(body, locale: "en") } is StringsParseError)
    }
    return passed.sorted()
}

let passed = try controls()
let data = try JSONSerialization.data(withJSONObject: ["passed": passed], options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
