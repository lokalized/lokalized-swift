import Foundation
import Lokalized

public extension ConformanceRunner {
    /// Native single-catalog component checks, without locale fallback, failure
    /// handlers or a fabricated public get/getResult observation.
    static func fragmentSelfTest() throws -> Int {
        var checks = 0
        let recorder = FragmentCallRecorder()
        func expect(_ value: Bool, _ detail: String) throws {
            guard value else { throw ConformanceError("Fragment self-test failed: \(detail)") }
            checks += 1
        }
        func kernel(_ text: String, locale: String = "en", limits: TranslationRuntimeLimits = .defaults,
                    resolver: PhoneticResolver? = nil) throws -> CompiledCatalogResolution {
            try .init(LocalizedStringLoader.parse(text, locale: locale), locale: LocaleTag(locale),
                      runtimeLimits: limits, phoneticResolver: resolver)
        }
        func rendered(_ kernel: CompiledCatalogResolution, _ values: [ExactString: PlaceholderValue] = [:], key: ExactString = "k") throws -> String {
            guard case .translation(let text, _) = try kernel.resolve(key, placeholders: values) else {
                throw ConformanceError("Fragment self-test expected a component translation")
            }
            return text
        }
        func failure(_ action: () throws -> Void) throws -> TranslationEvaluationError {
            do { try action() }
            catch let error as TranslationEvaluationError { checks += 1; return error }
            throw ConformanceError("Fragment self-test expected a categorized component failure")
        }
        let delimiter = try StringInterpolator.interpolate("{{x}}\u{0301}") { _, _ in "A" }
        try expect(delimiter.value == "A\u{0301}", "combining mark cannot hide closing braces")
        try expect(try StringInterpolator.placeholderNamesIn("{{é}} {{e\u{0301}}} {{é}}") == ["é", "e\u{0301}"], "UTF16-exact names and source order")
        let escaped = try StringInterpolator.interpolate(#"\{{name}} \\{{name}} \}} \{{unclosed"#) { _, _ in "V" }
        try expect(escaped.value == #"{{name}} \V }} {{unclosed"#, "escape scanner keeps Java delimiter rules")
        let lenient = try StringInterpolator.interpolate("}} {{bad name}} {{open", strict: false) { _, _ in "unused" }
        try expect(lenient.value == "}} {{bad name}} {{open" && lenient.unresolvedPlaceholderNames.isEmpty, "lenient malformed literals remain literal")
        let unresolved = try StringInterpolator.interpolate("{{b}} {{a}} {{b}}") { _, _ in nil }
        try expect(unresolved.unresolvedPlaceholderNames == ["b", "a"], "unresolved references deduplicate in first appearance order")
        let index = try failure { _ = try StringInterpolator.placeholderNamesIn("😀}}") }
        try expect(index.message == "Unexpected placeholder closing delimiter '}}' at index 2", "scanner offsets count UTF16")

        let literal = try kernel(#"{"k":"{{x}}/{{é}}/{{e\u0301}}"}"#)
        try expect(try rendered(literal, ["x": .text("{{other}}"), "é": .text("C"), "e\u{0301}": .text("D")]) == "{{other}}/C/D", "caller text is literal and exact keys stay distinct")
        if case .missingTranslation = try literal.resolve("absent", placeholders: [:]) { checks += 1 }
        else { throw ConformanceError("Fragment self-test expected missingTranslation") }
        let terminal = try kernel(#"{"k":{"translation":"root","alternatives":[{"take == 1":{"alternatives":[{"inner == 1":"nested"}]}},{"later == 1":"sibling"}]}}"#)
        if case .noMatchingAlternative = try terminal.resolve("k", placeholders: ["take": .integer(1), "inner": .integer(0), "later": .integer(1)]) { checks += 1 }
        else { throw ConformanceError("Fragment self-test expected terminal unmatched subtree") }
        let inherited = try kernel(#"{"k":{"translation":"root","placeholders":{"x":{"translation":"root-x"},"y":{"translation":"root-y"}},"alternatives":[{"take == 1":{"placeholders":{"x":{"translation":"child-x"}},"alternatives":[{"inner == 1":"{{x}}/{{y}}"}]}}]}}"#)
        guard case .translation(let inheritedText, let selectedPath) = try inherited.resolve("k", placeholders: ["take": .integer(1), "inner": .integer(1)]) else {
            throw ConformanceError("Fragment self-test expected inherited selection")
        }
        try expect(inheritedText == "child-x/root-y" && selectedPath == "k -> alternative[take == 1] -> alternative[inner == 1]", "nearest scope replaces by name and records selected path")
        let raw = try kernel(#"{"k":{"translation":"{{source}}/{{branch}}","placeholders":{"source":{"translation":"1"},"branch":{"translation":"default","alternatives":[{"source == 1":"selected"}]}}}}"#)
        let rawFailure = try failure { _ = try rendered(raw) }
        try expect(rawFailure.kind == .expression && rawFailure.message.contains("Unable to evaluate generated-fragment expression 'source == 1'"), "generated values never become predicate inputs")
        try expect(try rendered(raw, ["source": .integer(1)]) == "1/selected", "raw selector input is independent from generated replacement")
        let defaultEmpty = try kernel(#"{"k":{"translation":"x{{a}}x","placeholders":{"a":{"translation":"","alternatives":[{"take == 1":"{{unused}}"}]}}}}"#)
        try expect(try rendered(defaultEmpty, ["take": .integer(0)]) == "xx", "empty fragment default is a successful value")
        let cycleUnused = try kernel(#"{"k":{"translation":"ok","placeholders":{"a":{"translation":"{{a}}"}}}}"#)
        try expect(try rendered(cycleUnused) == "ok", "unreached generated cycles are lazy")
        let mixedCycle = try kernel(#"{"k":{"translation":"{{a}}","placeholders":{"a":{"translation":"{{b}}"},"b":{"value":"g","translations":{"GENDER_MASCULINE":"{{a}}"}}}}}"#)
        let cycle = try failure { _ = try rendered(mixedCycle, ["g": .languageForm(.gender(.masculine))]) }
        try expect(cycle.kind == .invalidState && cycle.message.contains("Generated placeholder cycle for key 'k': a -> b -> a"), "mixed generated kinds share cycle path")
        try expect(cycle.message.contains("selected default translation") && cycle.cause is TranslationEvaluationError, "cycle keeps contextual category and immediate cause")
        let selectionFirst = try kernel(#"{"k":{"translation":"{{a}} {{z}}","placeholders":{"a":{"translation":"{{a}}"},"z":{"value":"absent","translations":{"GENDER_MASCULINE":"z"}}}}}"#)
        let beforeCycle = try failure { _ = try rendered(selectionFirst) }
        try expect(beforeCycle.kind == .invalidArgument && beforeCycle.message.contains("generated placeholder 'z'") && !beforeCycle.message.contains("cycle"), "selection queue finishes before recursive cycle diagnosis")

        let aliases = try kernel(#"{"k":{"translation":"{{a}}/{{a}}/{{b}}","placeholders":{"a":{"value":"term","translations":{"PHONETIC_VOWEL":"V"}},"b":{"value":"term","translations":{"PHONETIC_VOWEL":"V"}}}}}"#, resolver: { term, locale in
            recorder.append(term, locale: locale); return .vowel
        })
        recorder.reset()
        try expect(try rendered(aliases, ["term": .text("word")]) == "V/V/V", "referenced generated values render repeatedly")
        try expect(recorder.snapshot().map(\.0) == ["word", "word"], "generated selection once per name, not once per shared raw source")
        _ = try rendered(aliases, ["term": .text("word")])
        try expect(recorder.snapshot().count == 4, "generated selection caches are per attempt")
        let supplying = try kernel(#"{"k":{"translation":"{{a}}","placeholders":{"a":{"value":"term","translations":{"PHONETIC_VOWEL":"V"}}}}}"#, locale: "fr", resolver: { term, locale in
            recorder.append(term, locale: locale); return .vowel
        })
        recorder.reset(); _ = try rendered(supplying, ["term": .text("mot")])
        try expect(recorder.snapshot().map { $0.1.tag } == ["fr"], "resolver receives supplying locale")
        let boundedTerm = try kernel(#"{"k":{"translation":"{{a}}","placeholders":{"a":{"value":"term","translations":{"PHONETIC_VOWEL":"V"}}}}}"#, limits: TranslationRuntimeLimits(maximumInterpolatedOutputCharacters: 3), resolver: { term, locale in
            recorder.append(term, locale: locale); return .vowel
        })
        recorder.reset()
        let termFailure = try failure { _ = try rendered(boundedTerm, ["term": .text("long")]) }
        try expect(termFailure.message.contains("Phonetic input for placeholder 'term' in key 'k' exceeds the maximum of 3 characters") && recorder.snapshot().isEmpty, "phonetic input bound is checked before callback")
        let retained = FragmentApplicationError()
        let callback = try kernel(#"{"k":{"translation":"{{a}}","placeholders":{"a":{"value":"term","translations":{"PHONETIC_VOWEL":"V"}}}}}"#, resolver: { _, _ in throw retained })
        do { _ = try rendered(callback, ["term": .text("word")]); throw ConformanceError("Expected retained application failure") }
        catch let error as FragmentApplicationError { try expect(error === retained, "unknown application error retains object identity") }

        let memo = try kernel(#"{"k":{"translation":"{{branch}}{{branch}}","placeholders":{"branch":{"translation":"{{leaf}}/{{leaf}}"},"leaf":{"translation":"abc"}}}}"#, limits: TranslationRuntimeLimits(maximumGeneratedExpansionCharacters: 10))
        try expect(try rendered(memo) == "abc/abcabc/abc", "memoized child and repeated parent expand once; cumulative child+parent is 10")
        let cumulative = try kernel(#"{"k":{"translation":"{{branch}}","placeholders":{"branch":{"translation":"{{leaf}}/{{leaf}}"},"leaf":{"translation":"abc"}}}}"#, limits: TranslationRuntimeLimits(maximumGeneratedExpansionCharacters: 9))
        let cumulativeFailure = try failure { _ = try rendered(cumulative) }
        try expect(cumulativeFailure.kind == .invalidState && cumulativeFailure.message.contains("cumulative limit of 9 characters"), "nested child and parent both consume expansion budget")
        let noGenerated = try kernel(#"{"k":"plain"}"#, limits: TranslationRuntimeLimits(maximumGeneratedExpansionCharacters: 0))
        try expect(try rendered(noGenerated) == "plain", "top-level output is not a generated expansion")
        let emptyBudget = try kernel(#"{"k":{"translation":"{{a}}{{a}}","placeholders":{"a":{"translation":""}}}}"#, limits: TranslationRuntimeLimits(maximumGeneratedExpansionCharacters: 0))
        try expect(try rendered(emptyBudget).isEmpty, "empty memoized expansion consumes zero")
        let depth = try kernel(#"{"k":{"translation":"{{a}}","placeholders":{"a":{"translation":"A"}}}}"#, limits: TranslationRuntimeLimits(maximumGeneratedPlaceholderDepth: 0))
        let depthFailure = try failure { _ = try rendered(depth) }
        try expect(depthFailure.message.contains("maximum depth of 0: [a]"), "generated depth zero refuses first reached expansion")
        let outputBeforeBudget = try kernel(#"{"k":{"translation":"{{a}}","placeholders":{"a":{"translation":"12345"}}}}"#, limits: TranslationRuntimeLimits(maximumInterpolatedOutputCharacters: 4, maximumGeneratedExpansionCharacters: 0))
        let outputFailure = try failure { _ = try rendered(outputBeforeBudget) }
        try expect(outputFailure.message.contains("Interpolated output exceeds the maximum of 4 characters") && !outputFailure.message.contains("cumulative"), "output refusal precedes cumulative charge")
        let unicodeLimit = try kernel(#"{"k":{"translation":"{{a}}{{a}}","placeholders":{"a":{"translation":"😀"}}}}"#, limits: TranslationRuntimeLimits(maximumInterpolatedOutputCharacters: 2, maximumGeneratedExpansionCharacters: 2))
        let unicodeFailure = try failure { _ = try rendered(unicodeLimit) }
        try expect(unicodeFailure.message == "Interpolated output exceeds the maximum of 2 characters", "UTF16 output bound counts repeated top-level insertions without generated wrappers")

        let firstCompile = #"{"k":{"translation":"unused","placeholders":{"z":{"translation":"z","alternatives":[{"longZ == 1":"yes"}]},"a":{"translation":"a","alternatives":[{"longA == 1":"yes"}]}}}}"#
        let compileFailure = try failure { _ = try kernel(firstCompile, limits: TranslationRuntimeLimits(maximumExpressionCharacters: 4)) }
        try expect(compileFailure.kind == .expression && compileFailure.message.contains("placeholder 'z'"), "eager compilation retains authored z-before-a declaration order")
        let eagerBranch = try failure {
            _ = try kernel(#"{"k":{"translation":"unused","alternatives":[{"1==1":"ok"},{"longName == 1":"unreachable"}]}}"#, limits: TranslationRuntimeLimits(maximumExpressionCharacters: 4))
        }
        try expect(eagerBranch.message.contains("whole-message alternative expression 'longName == 1'"), "unreached whole-message predicates compile against instance limits")
        let wrongNominal = try kernel(#"{"k":{"translation":"{{a}}","placeholders":{"a":{"value":"g","translations":{"GENDER_MASCULINE":"M"}}}}}"#)
        let nominalFailure = try failure { _ = try rendered(wrongNominal, ["g": .text("GENDER_MASCULINE")]) }
        try expect(nominalFailure.message.contains("must be a Gender but was String"), "constant-spelling text does not become a tagged form")
        let range = try kernel(#"{"k":{"translation":"{{a}}","placeholders":{"a":{"range":{"start":"s","end":"e"},"translations":{"CARDINALITY_OTHER":"range"}}}}}"#)
        try expect(try rendered(range, ["s": .languageForm(.cardinality(.one)), "e": .languageForm(.cardinality(.other))]) == "range", "range selectors support explicit categories")
        let rangeFailure = try failure { _ = try rendered(range, ["s": .text("1"), "e": .integer(2)]) }
        try expect(rangeFailure.message.contains("Range start placeholder 's' in key 'k' must be a Number, PluralOperands, or Cardinality but was String"), "range endpoint accept-set diagnosis names start")
        let nullable = try failure { _ = try rendered(literal, ["x": .null, "é": .text("C"), "e\u{0301}": .text("D")]) }
        try expect(nullable.message == "Missing value for placeholder(s) [x] in key 'k'", "explicit null remains unresolved")
        let missingCaller = try kernel(#"{"k":"{{missing}}"}"#)
        recorder.reset()
        let missingRender = try failure {
            _ = try missingCaller.resolve("k", placeholders: [:], callerValueRenderer: { _, _, _ in
                recorder.append("display", locale: try LocaleTag("en")); return "fabricated"
            })
        }
        try expect(missingRender.message == "Missing value for placeholder(s) [missing] in key 'k'" && recorder.snapshot().isEmpty,
                   "missing values never invoke the application caller renderer")
        let renderer = try literal.resolve("k", placeholders: ["x": .text("v"), "é": .text("C"), "e\u{0301}": .text("D")], callerValueRenderer: { _, value, remaining in
            guard let text = try value.interpolationText(maximumCharacters: remaining) else { return nil }
            return "[" + text + "]"
        })
        if case .translation(let text, _) = renderer { try expect(text == "[v]/[C]/[D]", "later bounded caller renderer seam does not touch generated values") }
        else { throw ConformanceError("Expected custom caller rendering") }
        return checks
    }
}

private final class FragmentApplicationError: Error, Sendable {}
/// Development-only callback recorder; all mutable state is protected by lock.
private final class FragmentCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(String, LocaleTag)] = []
    func append(_ text: String, locale: LocaleTag) { lock.lock(); defer { lock.unlock() }; calls.append((text, locale)) }
    func reset() { lock.lock(); defer { lock.unlock() }; calls = [] }
    func snapshot() -> [(String, LocaleTag)] { lock.lock(); defer { lock.unlock() }; return calls }
}
