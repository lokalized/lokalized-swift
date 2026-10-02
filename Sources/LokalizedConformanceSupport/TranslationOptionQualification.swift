import Lokalized

public extension ConformanceRunner {
    /// Per-call negotiation conveniences preserve diagnostics and error identity.
    static func translationOptionSelfTest() throws -> Int {
        var checks = 0
        func expect(_ value: @autoclosure () throws -> Bool, _ label: String) throws {
            guard try value() else { throw ConformanceError("Translation option qualification failed: \(label)") }
            checks += 1
        }
        let matcher = try DefaultLocaleMatcher(supportedLocales: ["en", "fr"], fallbackLocale: "en")
        try expect(BuildMetadata.current.localeDataMode == "pinned", "public locale data mode")
        try expect(BuildMetadata.current.cardinalityMode == "exact", "public cardinality mode")
        try expect(try LanguageRange.parse("fr;q=0.8,en;q=0.2") == matcher.parseLanguageRanges("fr;q=0.8,en;q=0.2"), "standalone strict parser shares the pinned kernel")
        let oversized = String(repeating: "fr,", count: 1_400) + "fr"
        for header in [nil, "", " \t ", ", ,", "fr;q=2", "not a header!", oversized] as [String?] {
            let options = try TranslationOptions.forAcceptLanguage(header, using: matcher)
            guard let match = options.localeMatchResult else { throw ConformanceError("Missing option match") }
            try expect(match.locale == nil && match.matchType == .noMatch && match.requestedLanguageRanges.isEmpty,
                       "fail-soft header returns an honest unmatched empty diagnostic")
            try expect(options.locale == nil && options.languageRanges == nil && match.fallbackLocale == "en",
                       "header options contain only negotiated context")
        }
        let unmatched = try TranslationOptions.forAcceptLanguage("de", using: matcher).localeMatchResult!
        try expect(unmatched.locale == nil && unmatched.requestedLanguageRanges == [LanguageRange("de")], "usable unmatched preference remains visible")
        let normalized = try TranslationOptions.forAcceptLanguage(", \tfr;q=0.8,, en;q=0.2,", using: matcher).localeMatchResult!
        try expect(normalized.locale == "fr" && normalized.effectiveWeight == 0.8, "normalized weighted header negotiates")
        let excluded = try TranslationOptions.forAcceptLanguage("fr;q=0, *;q=1", using: matcher).localeMatchResult!
        try expect(excluded.locale == "en", "specific zero quality excludes a wildcard candidate")
        let longRanges = try matcher.parseLanguageRanges(oversized)
        try expect(try LanguageRange.parse(oversized) == longRanges, "standalone strict parser has no fail-soft header cap")
        try expect(try TranslationOptions.forLanguageRanges(longRanges, using: matcher).localeMatchResult?.locale == "fr", "strict ranges have no raw header length limit")
        let deferred = try TranslationOptions.forLanguageRanges([LanguageRange("fr")])
        try expect(deferred.localeMatchResult == nil && deferred.languageRanges == [LanguageRange("fr")], "original factory remains deferred")
        let expanded33 = (0..<33).map { "fr-x-\($0)" }.joined(separator: ",")
        let expanded32 = (0..<32).map { "fr-x-\($0)" }.joined(separator: ",")
        try expect(try LanguageRange.parse(expanded33).count == 33, "standalone parsing imposes no matcher count cap")
        try expect(try TranslationOptions.forAcceptLanguage(expanded33, using: matcher).localeMatchResult?.requestedLanguageRanges.isEmpty == true,
                   "33 ranges refused whole")
        try expect(try TranslationOptions.forAcceptLanguage(expanded32, using: matcher).localeMatchResult?.requestedLanguageRanges.count == 32,
                   "32 ranges retained whole")
        try expect(try TranslationOptions.forAcceptLanguage("he,id,yi,cmn,yue,nan,hak,jbo,tlh,gan,wuu,hsn,ase,fr;q=0.1", using: matcher)
            .localeMatchResult?.requestedLanguageRanges.isEmpty == true, "IANA expansion crossing 32 refuses the whole header")
        try expect(try TranslationOptions.forAcceptLanguage("he,id,yi,cmn,yue,nan,jbo,tlh,gan,wuu,hsn,ase,fr;q=0.9,de;q=0.8,es;q=0.7,it;q=0.6", using: matcher)
            .localeMatchResult?.requestedLanguageRanges.count == 32, "IANA expansion at 32 preserves every range")
        var strictRefused = false
        do { _ = try TranslationOptions.forLanguageRanges(matcher.parseLanguageRanges(expanded33), using: matcher) }
        catch { strictRefused = error is TranslationEvaluationError }
        try expect(strictRefused, "strict negotiated range cap is enforced before matching")
        let known = try matcher.matchFor([LanguageRange("fr")])
        let identity = OptionMatcherProbe(result: known)
        try expect(try TranslationOptions.forLanguageRanges([LanguageRange("fr")], using: identity).localeMatchResult === known,
                   "range factory preserves matcher result identity")
        try expect(try TranslationOptions.forAcceptLanguage("fr", using: identity).localeMatchResult === known,
                   "header factory preserves matcher result identity")
        let marker = OptionMarkerError()
        for (label, probe, header) in [
            ("custom parser error", OptionMatcherProbe(result: known, parserError: marker), "fr"),
            ("valid negotiation error", OptionMatcherProbe(result: known, negotiationError: marker), "fr"),
            ("empty negotiation error", OptionMatcherProbe(result: known, negotiationError: marker), "fr;q=2")
        ] {
            var error: (any Error)?
            do { _ = try TranslationOptions.forAcceptLanguage(header, using: probe) } catch let thrown { error = thrown }
            try expect((error as? OptionMarkerError) === marker, label + " propagates unchanged")
        }
        let en = try LocaleTag("en"), fr = try LocaleTag("fr")
        let catalogs: [LocaleTag: LocalizedCatalog] = [
            en: LocalizedCatalog(strings: try LocalizedStringLoader.parse(#"{"k":"hello"}"#, locale: "en").strings),
            fr: LocalizedCatalog(strings: try LocalizedStringLoader.parse(#"{"k":"bonjour"}"#, locale: "fr").strings)]
        let runtime = try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { catalogs },
            localeSupplier: { _ in en }, fallbackLocale: en))
        let badHeaderOptions = try TranslationOptions.forAcceptLanguage("fr;q=2", using: runtime)
        let fallback = try runtime.getResult("k", options: badHeaderOptions)
        try expect(fallback.translation == "hello" && fallback.localeMatchResult === badHeaderOptions.localeMatchResult,
                   "runtime consumes unmatched header context and retains identity")
        try expect(fallback.localeMatchResult?.locale == nil && fallback.localeMatchResult?.matchType == .noMatch,
                   "fallback translation does not invent a negotiated match")
        let preferred = try TranslationOptions.forAcceptLanguage("fr-CH", using: runtime)
        let result = try runtime.getResult("k", options: preferred)
        try expect(result.translation == "bonjour" && result.localeMatchResult === preferred.localeMatchResult,
                   "runtime consumes the same successful negotiated record")
        return checks
    }
}

private final class OptionMarkerError: Error, Sendable {}
private struct OptionMatcherProbe: LocaleMatcher {
    let fallbackLocale = "en"
    let result: LocaleMatchResult
    var parserError: (any Error)?
    var negotiationError: (any Error)?
    func parseLanguageRanges(_ input: String) throws -> [LanguageRange] {
        if let parserError { throw parserError }
        return try LanguageRangeParser.parse(input)
    }
    func matchFor(_ ranges: [LanguageRange]) throws -> LocaleMatchResult {
        if let negotiationError { throw negotiationError }
        return result
    }
}
