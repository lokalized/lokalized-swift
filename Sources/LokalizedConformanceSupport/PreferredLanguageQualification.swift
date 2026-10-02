import Foundation
import Lokalized

public extension ConformanceRunner {
    /// Ordered preference selection is a native helper, not a new donor case.
    static func preferredLanguageSelfTest() throws -> Int {
        var checks = 0
        func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            checks += 1
            guard try value() else { throw ConformanceError("Preferred-language self-test failed: \(message)") }
        }
        func thrown(_ action: () throws -> Void) throws -> any Error {
            checks += 1
            do { try action() } catch { return error }
            throw ConformanceError("Expected preferred-language matcher error")
        }
        try expect(PreferredLanguageChooser.maximumPreferredLanguages == 32, "raw preference cap")
        let base = try DefaultLocaleMatcher(supportedLocales: ["en", "fr", "zh-Hant"], fallbackLocale: "en")
        let recorder = PreferenceRecorder()
        let matcher = PreferenceProbeMatcher(base: base, recorder: recorder)
        let chosen = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["zz", "ZH-tw", "fr"], using: matcher)
        try expect(chosen.locale == "zh-Hant", "advance past unsupported preference; first genuine direct match")
        try expect(recorder.raw == ["zz", "ZH-tw"], "raw spelling retained and later preference unexamined")
        try expect(chosen === recorder.results.last, "returned match identity retained")
        try expect(chosen.requestedLanguageRanges.map(\.range) == ["zh-tw"], "diagnostics describe selected direct request only")
        try expect(recorder.rangeRequests.isEmpty && recorder.headerCalls == 0 && recorder.bestMatchCalls == 0,
                   "ordered chooser does not use header, weighted list or best-match APIs")
        let first = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["en", "fr"], using: base)
        try expect(first.locale == "en" && first.matchType == .exact, "first matched preference wins")
        for preferences in [[], ["zz", "qaa"], ["!!", ""]] {
            let exhaustion = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(preferences, using: base)
            try expect(!exhaustion.isMatch && exhaustion.locale == nil && exhaustion.matchType == .noMatch, "exhaustion does not manufacture fallback match")
            try expect(exhaustion.fallbackLocale == "en" && exhaustion.requestedLanguageRanges.isEmpty, "empty-range fallback diagnostics")
            try expect(exhaustion.consideredLocaleTags == base.supportedLocaleTags, "fallback configuration preserved")
        }
        for malformed in ["", "not a tag!", "fr_CA", "en-*", "-fr", "zh-", "en-x-lvariant-NY"] {
            let record = PreferenceRecorder()
            let probe = PreferenceProbeMatcher(base: base, recorder: record)
            let result = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages([malformed, "fr"], using: probe)
            try expect(result.locale == "fr", "malformed native tag skipped")
            try expect(record.raw == ["fr"], "malformed entry never reaches custom matcher")
        }
        for filler in ["!!", "qaa"] {
            let atBoundary = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(Array(repeating: filler, count: 31) + ["fr"], using: base)
            let outside = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(Array(repeating: filler, count: 32) + ["fr"], using: base)
            try expect(atBoundary.locale == "fr", "raw entry 32 examined")
            try expect(!outside.isMatch && outside.fallbackLocale == "en", "raw entry 33 silently ignored")
        }
        let boundedRecord = PreferenceRecorder()
        let boundedProbe = PreferenceProbeMatcher(base: base, recorder: boundedRecord)
        let bounded = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(Array(repeating: "qaa", count: 40), using: boundedProbe)
        try expect(boundedRecord.raw.count == 32 && boundedRecord.rangeRequests == [[]], "32 direct calls then one empty-range fallback")
        try expect(bounded === boundedRecord.results.last, "fallback match identity retained")

        let sign = try DefaultLocaleMatcher(supportedLocales: ["en", "nsi", "nsl"], fallbackLocale: "en")
        let signDirect = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["sgn-NO"], using: sign)
        let signRanges = try sign.matchFor(sign.parseLanguageRanges("sgn-NO"))
        try expect(signDirect.locale == "nsl", "direct sign-language identity")
        try expect(signRanges.locale == "nsi", "IANA-expanded weighted selection intentionally differs")
        let chinese = try DefaultLocaleMatcher(supportedLocales: ["cmn", "en", "mo", "ro", "zh"], fallbackLocale: "en",
            tiebreakerLocalesByLanguageCode: ["ro": ["mo", "ro"], "zh": ["cmn", "zh"]])
        let chineseDirect = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["zh-cmn"], using: chinese)
        let chineseRanges = try chinese.matchFor(chinese.parseLanguageRanges("zh-cmn"))
        try expect(chineseDirect.locale == "cmn" && chineseDirect.languageRange?.range == "cmn", "direct extlang projection")
        try expect(chineseRanges.locale == "zh", "extlang header equivalent expansion is separate")
        let en = try LocaleTag("en")
        let namedUnd = LocaleTag.forLanguageTag("UND-x-foo")
        let rootPrivate = LocaleTag.forLanguageTag("und-x-foo")
        let typed = try DefaultLocaleMatcher(supportedLocales: [en, namedUnd, rootPrivate], fallbackLocale: en)
        let typedRecord = PreferenceRecorder()
        let typedMatch = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["UND-x-foo"],
            using: PreferenceProbeMatcher(base: typed, recorder: typedRecord))
        try expect(namedUnd != rootPrivate && namedUnd.tag != rootPrivate.tag, "native identity discriminator")
        try expect(!typedMatch.isMatch && typedMatch.fallbackLocaleTag == en,
                   "uppercase UND must not be normalized a second time into root private use")
        try expect(typedRecord.raw == ["UND-x-foo"], "custom matcher receives original preference")
        let privateMatch = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["und-x-foo"], using: typed)
        try expect(privateMatch.localeTag == rootPrivate, "lowercase root preference remains distinct")

        let elected = try DefaultLocaleMatcher(supportedLocales: ["hy-AM", "hy-SU"], fallbackLocale: "hy-810",
                                               tiebreakerLocalesByLanguageCode: ["hy": ["hy-SU", "hy-AM"]])
        let reversed = try DefaultLocaleMatcher(supportedLocales: ["hy-AM", "hy-SU"], fallbackLocale: "hy-810",
                                                tiebreakerLocalesByLanguageCode: ["hy": ["hy-AM", "hy-SU"]])
        let fallback = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages([], using: elected)
        let reversedFallback = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["zz"], using: reversed)
        try expect(!fallback.isMatch && fallback.fallbackLocale == "hy-SU", "resolved fallback retains authored supplying tag")
        try expect(!reversedFallback.isMatch && reversedFallback.fallbackLocale == "hy-AM", "fallback tiebreaker remains instance-specific")

        let marker = PreferenceMarkerError()
        let directError = try thrown {
            _ = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["fr", "en"], using:
                PreferenceProbeMatcher(base: base, recorder: PreferenceRecorder(), directError: marker))
        }
        try expect((directError as? PreferenceMarkerError) === marker, "custom matcher error propagates by reference")
        let localeError = LocaleTagError(.malformedLanguageTag, "application matcher marker")
        let knownTypeError = try thrown {
            _ = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["fr", "en"], using:
                PreferenceProbeMatcher(base: base, recorder: PreferenceRecorder(), directError: localeError))
        }
        try expect((knownTypeError as? LocaleTagError) == localeError, "matcher errors are not mistaken for local validation errors")
        let emptyError = try thrown {
            _ = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages([], using:
                PreferenceProbeMatcher(base: base, recorder: PreferenceRecorder(), rangesError: marker))
        }
        try expect((emptyError as? PreferenceMarkerError) === marker, "fallback matcher error propagates unchanged")

        let other = try DefaultLocaleMatcher(supportedLocales: ["ja", "zh-Hant"], fallbackLocale: "ja")
        let firstContext = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["fr", "zh-TW"], using: base)
        let secondContext = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["fr", "zh-TW"], using: other)
        try expect(firstContext.locale == "fr" && secondContext.locale == "zh-Hant", "independent contexts coexist")
        let failures = PreferenceConcurrentFailures()
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            do {
                let preferences = index % 2 == 0 ? ["fr"] : ["zh-TW"]
                let matcher = index % 2 == 0 ? base : other
                let expected = index % 2 == 0 ? "fr" : "zh-Hant"
                let result = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(preferences, using: matcher)
                if result.locale != expected { failures.add("Incorrect independent preferred-language result") }
            } catch { failures.add(String(describing: error)) }
        }
        try expect(failures.values.isEmpty, "concurrent independent preference contexts")
        return checks
    }
}

private final class PreferenceMarkerError: Error, Sendable {}
private struct PreferenceProbeMatcher: LocaleMatcher {
    let base: DefaultLocaleMatcher
    let recorder: PreferenceRecorder
    var directError: (any Error)? = nil
    var rangesError: (any Error)? = nil
    var fallbackLocale: String { base.fallbackLocale }
    func matchFor(_ locale: String) throws -> LocaleMatchResult {
        recorder.direct(locale)
        if let directError { throw directError }
        let result = try base.matchFor(locale)
        recorder.result(result)
        return result
    }
    func matchFor(_ ranges: [LanguageRange]) throws -> LocaleMatchResult {
        recorder.ranges(ranges)
        if let rangesError { throw rangesError }
        let result = try base.matchFor(ranges)
        recorder.result(result)
        return result
    }
    func parseLanguageRanges(_ header: String) throws -> [LanguageRange] {
        recorder.header()
        throw ConformanceError("Ordered chooser called the weighted header parser")
    }
    func bestMatchFor(_ locale: String) throws -> String {
        recorder.bestMatch()
        throw ConformanceError("Ordered chooser called bestMatchFor")
    }
}
private final class PreferenceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var directRequests: [String] = []
    private var weightedRequests: [[LanguageRange]] = []
    private var returnedResults: [LocaleMatchResult] = []
    private var headers = 0
    private var bestMatches = 0
    var raw: [String] { lock.lock(); defer { lock.unlock() }; return directRequests }
    var rangeRequests: [[LanguageRange]] { lock.lock(); defer { lock.unlock() }; return weightedRequests }
    var results: [LocaleMatchResult] { lock.lock(); defer { lock.unlock() }; return returnedResults }
    var headerCalls: Int { lock.lock(); defer { lock.unlock() }; return headers }
    var bestMatchCalls: Int { lock.lock(); defer { lock.unlock() }; return bestMatches }
    func direct(_ value: String) { lock.lock(); defer { lock.unlock() }; directRequests.append(value) }
    func ranges(_ value: [LanguageRange]) { lock.lock(); defer { lock.unlock() }; weightedRequests.append(value) }
    func result(_ value: LocaleMatchResult) { lock.lock(); defer { lock.unlock() }; returnedResults.append(value) }
    func header() { lock.lock(); defer { lock.unlock() }; headers += 1 }
    func bestMatch() { lock.lock(); defer { lock.unlock() }; bestMatches += 1 }
}
private final class PreferenceConcurrentFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var values: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    func add(_ value: String) { lock.lock(); defer { lock.unlock() }; recorded.append(value) }
}
