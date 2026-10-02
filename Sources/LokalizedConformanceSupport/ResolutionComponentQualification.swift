import CryptoKit
import Foundation
import Lokalized

/// A deliberately partial observation of frozen whole-runtime cases. No ID in
/// this report is promoted into ConformanceReport.runtimePassed.
public struct ResolutionComponentReport: Encodable, Sendable {
    public let scope = "single-catalog-component-projection"
    public let status: String
    public let totalCorpusCases: Int
    public let eligibleComponentIDs: [String]
    public let eligibleIDsSHA256: String
    public let projectedComponentsPassed: [String]
    public let failed: [ConformanceFailure]
    public let projectedFields = ["outcome", "translation", "error.type", "error.message", "error.causeType", "error.causeMessage", "resolverCalls"]
    public let unexaminedWholeCaseChannels = ["match", "result metadata", "fallback policy", "failure handler", "result/failure identity", "successful fallback observation", "bidi policy"]
}

/// Replays input-driven direct donor attempts. Expectations are read only after
/// native decoding/compilation/resolution have produced an independent result.
public enum ResolutionComponentQualification {
    /// Discriminating native checks outside the frozen whole-runtime corpus.
    /// These exercise the package component rather than manufacturing results.
    static func runNative() throws -> Int {
        var checks = 0
        func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try value() else { throw ConformanceError("Native resolution component: " + message) }
            checks += 1
        }
        func kernel(_ source: String, limits: TranslationRuntimeLimits = .defaults,
                    resolver: PhoneticResolver? = nil) throws -> CompiledCatalogResolution {
            let catalog = try LocalizedStringLoader.parse(Data(source.utf8), locale: "en", source: "native")
            return try CompiledCatalogResolution(catalog, locale: LocaleTag("en"), runtimeLimits: limits, phoneticResolver: resolver)
        }
        func text(_ outcome: CatalogResolutionOutcome) throws -> String {
            guard case .translation(let value, _) = outcome else { throw ConformanceError("Native component expected translation") }
            return value
        }
        let accent = "\u{301}"
        let reference = try StringInterpolator.interpolate("{{name}}" + accent, replacement: { name, _ in name == "name" ? "ok" : nil })
        try expect(ExactString(reference.value) == ExactString("ok" + accent), "combining mark after closing delimiter")
        let escaped = try StringInterpolator.interpolate("\\{{name}}" + accent, replacement: { _, _ in throw ConformanceError("Escaped token was evaluated") })
        try expect(ExactString(escaped.value) == ExactString("{{name}}" + accent) && escaped.unresolvedPlaceholderNames.isEmpty,
                   "escaped token followed by combining mark remains literal")
        do {
            _ = try StringInterpolator.interpolate("😀}}" + accent, replacement: { _, _ in nil })
            throw ConformanceError("Native component accepted stray closing delimiter")
        } catch let error as TranslationEvaluationError {
            try expect(error.kind == .invalidArgument && error.message == "Unexpected placeholder closing delimiter '}}' at index 2",
                       "stray delimiter diagnostic counts UTF-16")
        }
        let unresolved = try StringInterpolator.placeholderNamesIn("{{é}}/{{e\u{301}}}/{{é}}")
        try expect(unresolved == [ExactString("é"), ExactString("e\u{301}")], "ordered NFC/NFD names remain distinct")
        let exact = try kernel(#"{"exact":{"translation":"default","alternatives":[{"é == GENDER_FEMININE && e\u0301 == GENDER_MASCULINE":{"translation":"matched"}}]},"slots":"{{é}}/{{e\u0301}}"}"#)
        try expect(try text(exact.resolve("exact", placeholders: ["é": .languageForm(.gender(.feminine)), ExactString("e\u{301}"): .languageForm(.gender(.masculine))])) == "matched",
                   "exact context identity in expression variables")
        try expect(try text(exact.resolve("slots", placeholders: ["é": .text("NFC"), ExactString("e\u{301}"): .text("NFD")])) == "NFC/NFD",
                   "exact context identity in interpolation")
        let literal = try kernel(#"{"literal":"{{caller}}","unused":{"translation":"safe","placeholders":{"bad":{"value":"term","translations":{"PHONETIC_VOWEL":"{{bad}}"}}}}}"#)
        try expect(try text(literal.resolve("literal", placeholders: ["caller": .text("{{poison}}")])) == "{{poison}}",
                   "caller text is never recursively expanded")
        try expect(try text(literal.resolve("unused", placeholders: [:])) == "safe", "unreachable selector and cycle remain lazy")
        let terminal = try kernel(#"{"terminal":{"translation":"root-default","alternatives":[{"mode == 1":{"alternatives":[{"other == 1":{"translation":"inner"}}]}},{"mode >= 1":{"translation":"later"}}]}}"#)
        if case .noMatchingAlternative = try terminal.resolve("terminal", placeholders: ["mode": .integer(1), "other": .integer(0)]) { checks += 1 }
        else { throw ConformanceError("Native component resumed a sibling after committing to a matching branch") }
        let fragment = try kernel(#"{"terminal":{"translation":"{{frag}}","placeholders":{"frag":{"translation":"default","alternatives":[{"count > 1":"{{missing}}"},{"count > 0":"later"}]}}}}"#)
        do {
            _ = try fragment.resolve("terminal", placeholders: ["count": .integer(2)])
            throw ConformanceError("Native component resumed fragment alternatives after selection failure")
        } catch let error as TranslationEvaluationError {
            try expect(error.message == "Unable to resolve generated placeholder 'frag' (ExpressionTranslation) for key 'terminal'; definition declared at terminal; selected expression 'count > 1': Missing value for placeholder(s) [missing] in key 'terminal'",
                       "terminal fragment error retains selected predicate context")
        }
        let nestedSource = #"{"budget":{"translation":"{{a}}/{{a}}","placeholders":{"a":{"translation":"{{b}}"},"b":{"translation":"abc"}}}}"#
        let six = try kernel(nestedSource, limits: TranslationRuntimeLimits(maximumGeneratedExpansionCharacters: 6))
        try expect(try text(six.resolve("budget", placeholders: [:])) == "abc/abc", "nested child and parent charge once; repeated name memoizes")
        let five = try kernel(nestedSource, limits: TranslationRuntimeLimits(maximumGeneratedExpansionCharacters: 5))
        do {
            _ = try five.resolve("budget", placeholders: [:])
            throw ConformanceError("Native component failed to charge nested parent expansion")
        } catch let error as TranslationEvaluationError {
            try expect(error.kind == .invalidState && error.message == "Unable to resolve generated placeholder 'a' (ExpressionTranslation) for key 'budget'; definition declared at budget; selected default translation: Generated placeholder expansion for key 'budget' exceeds the cumulative limit of 5 characters",
                       "cumulative expansion budget includes parent and child")
        }
        let sentinel = NativeSentinel("application-resolver-sentinel")
        let throwing = try kernel(#"{"custom":{"translation":"{{generated}}","placeholders":{"generated":{"value":"term","translations":{"PHONETIC_VOWEL":"vowel","PHONETIC_CONSONANT":"consonant"}}}}}"#,
                                  resolver: { _, _ in throw sentinel })
        do {
            _ = try throwing.resolve("custom", placeholders: ["term": .text("apple")])
            throw ConformanceError("Native component swallowed custom resolver failure")
        } catch let error as NativeSentinel {
            try expect(error === sentinel, "custom application error identity survives generated contextualization")
        }
        let recorder = Recorder()
        let order = try kernel(#"{"order":{"translation":"{{caller}}/{{generated}}","placeholders":{"generated":{"value":"term","translations":{"PHONETIC_VOWEL":"vowel","PHONETIC_CONSONANT":"consonant"}}}}}"#,
                               resolver: { _, _ in recorder.append(.string("resolver")); return .vowel })
        let caller = NativeDisplay(recorder: recorder)
        try expect(try text(order.resolve("order", placeholders: ["caller": .custom(caller), "term": .text("apple")])) == "caller/vowel",
                   "custom bounded display carrier renders")
        try expect(try JSONComparison.firstDifference(expected: .array([.string("resolver"), .string("display")]),
                                                       actual: .array(recorder.calls())) == nil,
                   "generated dependencies resolve before caller display conversions")
        let eager = #"{"eager":{"translation":"safe","placeholders":{"z":{"translation":"unused","alternatives":[{"longName == 1":"z"}]},"a":{"translation":"unused","alternatives":[{"longName == 2":"a"}]}}}}"#
        do {
            _ = try kernel(eager, limits: TranslationRuntimeLimits(maximumExpressionCharacters: 5))
            throw ConformanceError("Native component did not eagerly compile unreachable fragments")
        } catch let error as TranslationEvaluationError {
            try expect(error.message == "Unable to compile generated-fragment alternative 0 expression 'longName == 1' for placeholder 'z' declared at eager in root key 'eager' for locale 'en': Expression length 13 exceeds maximum supported length 5",
                       "eager compilation preserves authored fragment order")
        }
        return checks
    }

    public static func run(referenceDirectory: URL) throws -> ResolutionComponentReport {
        let corpus = try ConformanceRunner.load(referenceDirectory: referenceDirectory)
        var ids: [String] = [], passed: [String] = [], failures: [ConformanceFailure] = []
        var cache: [CacheKey: PreparedCatalog] = [:]
        for row in corpus.cases {
            guard let candidate = try candidate(row) else { continue }
            ids.append(row.id)
            do {
                let key = CacheKey(fixture: ExactString(try rowFixtureID(row)), locale: ExactString(candidate.locale.tag))
                let prepared: PreparedCatalog
                if let existing = cache[key] { prepared = existing }
                else {
                    let recorder = Recorder()
                    let options = try CatalogObservations.loadingOptions(candidate.fixture["loadingOptions"])
                    let file = try LocalizedStringLoader.parse(CatalogObservations.fileBytes(candidate.locale.tag,
                        fixture: candidate.fixture, materialized: row.materializedFiles), locale: candidate.locale.tag,
                        source: candidate.locale.tag, loadingOptions: options)
                    let kernel = try CompiledCatalogResolution(file, locale: candidate.locale,
                        runtimeLimits: limits(candidate.fixture["runtimeLimits"]),
                        phoneticResolver: resolver(candidate.fixture["phoneticResolver"], recorder: recorder))
                    prepared = PreparedCatalog(kernel: kernel, recorder: recorder)
                    cache[key] = prepared
                }
                prepared.recorder.reset()
                let actual = try observe(candidate, prepared: prepared)
                let expected = try expectedProjection(row)
                if let difference = try JSONComparison.firstDifference(expected: expected, actual: actual) {
                    failures.append(.init(id: row.id, detail: "Component projection: " + difference))
                } else { passed.append(row.id) }
            } catch {
                failures.append(.init(id: row.id, detail: "Component qualification: " + String(describing: error)))
            }
        }
        let digest = SHA256.hash(data: Data(ids.map { $0 + "\n" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(status: failures.isEmpty ? "passed" : "failed", totalCorpusCases: corpus.cases.count,
                     eligibleComponentIDs: ids, eligibleIDsSHA256: digest,
                     projectedComponentsPassed: passed, failed: failures)
    }

    private struct Candidate {
        let fixture: [ExactString: JSONValue]
        let input: [ExactString: JSONValue]
        let locale: LocaleTag
    }
    private struct CacheKey: Hashable { let fixture: ExactString; let locale: ExactString }
    private struct PreparedCatalog { let kernel: CompiledCatalogResolution; let recorder: Recorder }

    // BehavioralCase carries its materialized fixture but not its name. All rows
    // for the same fixture share these immutable file bytes and options; use the
    // digest as an exact local cache identity without relying on expected fields.
    private static func rowFixtureID(_ row: BehavioralCase) throws -> String {
        guard let files = row.materializedFiles else { throw ConformanceError("Component cases require materialized fixture bytes") }
        var bytes = Data()
        for name in files.keys.sorted() {
            bytes.append(contentsOf: name.string.utf8); bytes.append(0)
            bytes.append(files[name]!); bytes.append(0)
        }
        // Configuration participates too; two fixtures can share catalog bytes.
        if let fixture = row.fixture { bytes.append(try FixtureJSONWriter.bytes(fixture)) }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func candidate(_ row: BehavioralCase) throws -> Candidate? {
        guard row.operation == "getResult", let fixture = row.fixture else { return nil }
        let input = try row.input.checkedObject(at: "component.input")
        let allowed = Set(["key", "locale", "placeholders"].map { ExactString($0) })
        guard Set(input.keys).isSubset(of: allowed), case .string(let key) = input["key"],
              case .string(let tag) = input["locale"], let locale = try? LocaleTag(tag),
              ExactString(locale.tag) == ExactString(tag), !locale.isRightToLeft else { return nil }
        let fields = try fixture.checkedObject(at: "component.fixture")
        let files = try fields.value("files", at: "component.fixture").checkedObject(at: "component.fixture.files")
        guard let selected = files[ExactString(tag)] else { return nil }
        for name in ["constructionOverrides", "localeSupplier", "localeMatchSupplier", "translationFailureHandler", "bidiIsolation"] {
            guard case .null = fields[ExactString(name)] else { return nil }
        }
        guard case .bool(false) = fields["loadOnly"], case .bool(false) = fields["refusesConstruction"],
              try fields.value("entries", at: "component.fixture").checkedObject(at: "component.fixture.entries").isEmpty else { return nil }
        if case .object = fields["phoneticResolver"] {
            let config = try fields.value("phoneticResolver", at: "component.fixture").checkedObject(at: "component.resolver")
            let behavior = try config.string("behavior", at: "component.resolver")
            guard behavior != "return-null" else { return nil }
            if behavior == "by-term" || behavior == "by-locale" {
                guard case .string = config["default"] else { return nil }
            }
        }
        if files.count != 1 {
            guard case .null = fields["translationFallbackPolicy"],
                  let entry = try selected.checkedObject(at: "component.catalog")[ExactString(key)],
                  try completeAlternatives(entry) else { return nil }
        }
        return .init(fixture: fields, input: input, locale: locale)
    }

    /// Every selectable whole-message node has a default, so a successful donor
    /// cannot require a later catalog; errors stop under the default policy.
    private static func completeAlternatives(_ value: JSONValue) throws -> Bool {
        if case .string = value { return true }
        let fields = try value.checkedObject(at: "component.entry")
        guard case .string = fields["translation"] else { return false }
        guard let alternatives = fields["alternatives"] else { return true }
        guard case .array(let rows) = alternatives else { throw ConformanceError("Invalid component alternative array") }
        for row in rows {
            for child in try row.checkedObject(at: "component.alternative").values where try !completeAlternatives(child) { return false }
        }
        return true
    }

    private static func observe(_ candidate: Candidate, prepared: PreparedCatalog) throws -> JSONValue {
        let values: [ExactString: PlaceholderValue]
        do { values = try placeholders(candidate.input["placeholders"]) }
        catch { return try observation(outcome: "inputRefusal", error: error, calls: prepared.recorder.calls()) }
        do {
            switch try prepared.kernel.resolve(ExactString(candidate.input.string("key", at: "component.input")), placeholders: values) {
            case .translation(let text, _):
                return .object([.test("outcome", .string("translation")), .test("translation", .string(text)),
                                .test("resolverCalls", .array(prepared.recorder.calls()))])
            case .missingTranslation: return reason("missingTranslation", calls: prepared.recorder.calls())
            case .noMatchingAlternative: return reason("noMatchingAlternative", calls: prepared.recorder.calls())
            }
        } catch { return try observation(outcome: "resolutionFailure", error: error, calls: prepared.recorder.calls()) }
    }

    private static func expectedProjection(_ row: BehavioralCase) throws -> JSONValue {
        let fields = try row.expected.checkedObject(at: "component.expected")
        let calls: [JSONValue]
        if let value = fields["resolverCalls"] {
            guard case .array(let rows) = value else { throw ConformanceError("Invalid expected resolver trace") }
            calls = rows
        } else { calls = [] }
        if let thrown = fields["thrown"] {
            let object = try thrown.checkedObject(at: "component.expected.thrown")
            return .object([.test("outcome", .string("inputRefusal")), .test("error", .object([
                .test("type", try object.value("type", at: "thrown")), .test("message", try object.value("message", at: "thrown")),
                .test("causeType", try object.value("causeType", at: "thrown")), .test("causeMessage", .null)
            ])), .test("resolverCalls", .array(calls))])
        }
        let result = try fields.value("result", at: "component.expected").checkedObject(at: "component.expected.result")
        if case .string("TRANSLATED") = result["status"] {
            return .object([.test("outcome", .string("translation")),
                .test("translation", try result.value("translation", at: "result")), .test("resolverCalls", .array(calls))])
        }
        switch try result.string("failureReason", at: "component.expected.result") {
        case "MISSING_TRANSLATION": return reason("missingTranslation", calls: calls)
        case "NO_MATCHING_ALTERNATIVE": return reason("noMatchingAlternative", calls: calls)
        case "RESOLUTION_FAILURE":
            return .object([.test("outcome", .string("resolutionFailure")),
                .test("error", try result.value("failureCause", at: "component.expected.result")), .test("resolverCalls", .array(calls))])
        default: throw ConformanceError("Unrecognized component expectation")
        }
    }

    private static func reason(_ outcome: String, calls: [JSONValue]) -> JSONValue {
        .object([.test("outcome", .string(outcome)), .test("resolverCalls", .array(calls))])
    }
    private static func observation(outcome: String, error: any Error, calls: [JSONValue]) throws -> JSONValue {
        let (type, message, cause) = try errorFields(error)
        let immediate = try cause.map(errorFields)
        return .object([.test("outcome", .string(outcome)), .test("error", .object([
            .test("type", .string(type)), .test("message", .string(message)),
            .test("causeType", immediate.map { .string($0.0) } ?? .null),
            .test("causeMessage", immediate.map { .string($0.1) } ?? .null)
        ])), .test("resolverCalls", .array(calls))])
    }
    private static func errorFields(_ error: any Error) throws -> (String, String, (any Error)?) {
        switch error {
        case let error as TranslationEvaluationError:
            let type: String
            switch error.kind {
            case .expression: type = "com.lokalized.ExpressionEvaluationException"
            case .invalidArgument: type = "java.lang.IllegalArgumentException"
            case .invalidState: type = "java.lang.IllegalStateException"
            }
            return (type, error.message, error.cause)
        case let error as ExpressionCompilationError: return ("com.lokalized.ExpressionEvaluationException", error.message, nil)
        case let error as NumericError:
            let type: String
            switch error.kind {
            case .invalidArgument: type = "java.lang.IllegalArgumentException"
            case .invalidDecimal: type = "java.lang.NumberFormatException"
            case .roundingNecessary: type = "java.lang.ArithmeticException"
            }
            return (type, error.message, nil)
        case let error as UnsupportedLocaleError: return ("com.lokalized.UnsupportedLocaleException", error.message, nil)
        default: throw ConformanceError("Unregistered component error type: " + String(reflecting: type(of: error)))
        }
    }

    private static func placeholders(_ value: JSONValue?) throws -> [ExactString: PlaceholderValue] {
        guard let value else { return [:] }
        let fields = try value.checkedObject(at: "component.placeholders")
        var result: [ExactString: PlaceholderValue] = [:]
        for key in fields.keys.sorted() { result[key] = try placeholder(fields[key]!) }
        return result
    }
    private static func placeholder(_ value: JSONValue) throws -> PlaceholderValue {
        switch value {
        case .null: return .null
        case .string(let text): return .text(text)
        case .bool(let value): return .boolean(value)
        case .number(let text):
            if text.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }) {
                if let value = Int32(text) { return .integer(value) }
                if let value = Int64(text) { return .number(.integer(value)) }
                return .number(try .forBigInteger(text, runtimeLimits: .numericHardCeilings))
            }
            guard let value = LanguageRangeWeight.parse(text) else { throw ConformanceError("Invalid JSON double carrier") }
            return .number(.double(value))
        case .object:
            let fields = try value.checkedObject(at: "component.taggedPlaceholder", allowed: ["$lokalized", "value", "axis", "name", "renderName", "visibleDecimalPlaces", "compactExponent"])
            switch try fields.string("$lokalized", at: "component.taggedPlaceholder") {
            case "decimal": return .number(try .forDecimal(fields.string("value", at: "carrier"), runtimeLimits: .numericHardCeilings))
            case "bigint": return .number(try .forBigInteger(fields.string("value", at: "carrier"), runtimeLimits: .numericHardCeilings))
            case "integer":
                guard let value = Int32(try fields.string("value", at: "carrier")) else { throw ConformanceError("Invalid Integer carrier") }
                return .integer(value)
            case "long":
                guard let value = Int64(try fields.string("value", at: "carrier")) else { throw ConformanceError("Invalid Long carrier") }
                return .number(.integer(value))
            case "double":
                guard let value = LanguageRangeWeight.parse(try fields.string("value", at: "carrier")) else { throw ConformanceError("Invalid Double carrier") }
                return .number(.double(value))
            case "float":
                guard let value = Float(try fields.string("value", at: "carrier")) else { throw ConformanceError("Invalid Float carrier") }
                return .number(.float(value))
            case "plural-operands":
                return .pluralOperands(try PluralOperands(.forDecimal(fields.string("value", at: "carrier"), runtimeLimits: .numericHardCeilings),
                    visibleDecimalPlaces: integer(fields["visibleDecimalPlaces"]), compactExponent: integer(fields["compactExponent"])))
            case "language-form":
                let name = try fields.string("name", at: "carrier"), axis = try fields.string("axis", at: "carrier")
                guard let form = LanguageFormValue(rawValue: name), axisName(form.axis) == axis else { throw ConformanceError("Invalid language form carrier") }
                if let renderName = fields["renderName"] {
                    guard case .string(let text) = renderName, ExactString(text) == ExactString(form.displayName) else { throw ConformanceError("Invalid language form renderName") }
                }
                return .languageForm(form)
            default: throw ConformanceError("Unknown tagged placeholder carrier")
            }
        default: throw ConformanceError("Unsupported placeholder carrier shape")
        }
    }
    private static func axisName(_ axis: LanguageFormAxis) -> String {
        switch axis {
        case .grammaticalCase: "grammatical-case"
        default: axis.rawValue.lowercased()
        }
    }
    private static func integer(_ value: JSONValue?) throws -> Int? {
        guard let value else { return nil }
        guard case .number(let text) = value, let number = Int(text) else { throw ConformanceError("Invalid integer component option") }
        return number
    }
    private static func limits(_ value: JSONValue?) throws -> TranslationRuntimeLimits {
        if value == nil { return .defaults }
        if case .null = value { return .defaults }
        let fields = try value!.checkedObject(at: "component.runtimeLimits", allowed: [
            "maximumNumberPrecision", "maximumAbsoluteNumberScale", "maximumVisibleDecimalPlaces", "maximumCompactExponent",
            "maximumExpressionCharacters", "maximumExpressionTokens", "maximumExpressionNestingDepth", "maximumGeneratedPlaceholderDepth",
            "maximumInterpolatedOutputCharacters", "maximumGeneratedExpansionCharacters"
        ])
        let defaults = TranslationRuntimeLimits.defaults
        return try .init(maximumNumberPrecision: integer(fields["maximumNumberPrecision"]) ?? defaults.maximumNumberPrecision,
            maximumAbsoluteNumberScale: integer(fields["maximumAbsoluteNumberScale"]) ?? defaults.maximumAbsoluteNumberScale,
            maximumVisibleDecimalPlaces: integer(fields["maximumVisibleDecimalPlaces"]) ?? defaults.maximumVisibleDecimalPlaces,
            maximumCompactExponent: integer(fields["maximumCompactExponent"]) ?? defaults.maximumCompactExponent,
            maximumExpressionCharacters: integer(fields["maximumExpressionCharacters"]) ?? defaults.maximumExpressionCharacters,
            maximumExpressionTokens: integer(fields["maximumExpressionTokens"]) ?? defaults.maximumExpressionTokens,
            maximumExpressionNestingDepth: integer(fields["maximumExpressionNestingDepth"]) ?? defaults.maximumExpressionNestingDepth,
            maximumGeneratedPlaceholderDepth: integer(fields["maximumGeneratedPlaceholderDepth"]) ?? defaults.maximumGeneratedPlaceholderDepth,
            maximumInterpolatedOutputCharacters: integer(fields["maximumInterpolatedOutputCharacters"]) ?? defaults.maximumInterpolatedOutputCharacters,
            maximumGeneratedExpansionCharacters: integer(fields["maximumGeneratedExpansionCharacters"]) ?? defaults.maximumGeneratedExpansionCharacters)
    }

    private static func resolver(_ value: JSONValue?, recorder: Recorder) throws -> PhoneticResolver? {
        guard let value else { return nil }
        if case .null = value { return nil }
        let fields = try value.checkedObject(at: "component.resolver", allowed: ["behavior", "phonetic", "mapping", "default", "message"])
        let behavior = try fields.string("behavior", at: "component.resolver")
        func phonetic(_ name: String) throws -> Phonetic {
            guard let form = Phonetic(rawValue: name) else { throw ConformanceError("Unknown resolver form") }
            return form
        }
        let delegate: PhoneticResolver
        switch behavior {
        case "constant":
            let form = try phonetic(fields.string("phonetic", at: "component.resolver")); delegate = { _, _ in form }
        case "by-term", "by-locale":
            let source = try fields.value("mapping", at: "component.resolver").checkedObject(at: "component.resolver.mapping")
            var mapping: [ExactString: Phonetic] = [:]
            for (key, value) in source {
                guard case .string(let name) = value else { throw ConformanceError("Invalid resolver mapping") }
                mapping[key] = try phonetic(name)
            }
            let fixedMapping = mapping, fallback = try phonetic(fields.string("default", at: "component.resolver"))
            delegate = { term, locale in fixedMapping[ExactString(behavior == "by-term" ? term : locale.tag)] ?? fallback }
        case "first-letter-vowel":
            delegate = { term, _ in term.utf16.first.map { [65, 69, 73, 79, 85, 97, 101, 105, 111, 117].contains($0) } == true ? .vowel : .consonant }
        case "throw":
            let message = try fields["message"].map { value in
                guard case .string(let text) = value else { throw ConformanceError("Invalid resolver message") }; return text
            } ?? "phonetic resolver failed deliberately"
            delegate = { _, _ in throw TranslationEvaluationError(kind: .invalidState, message: message) }
        default: throw ConformanceError("Unrepresentable or unknown component resolver behavior")
        }
        return { term, locale in
            do {
                let result = try delegate(term, locale)
                recorder.append(.object([.test("term", .string(term)), .test("locale", .string(locale.tag)),
                    .test("returned", .string(result.displayName)), .test("threw", .null)]))
                return result
            } catch {
                let projected = try errorFields(error)
                recorder.append(.object([.test("term", .string(term)), .test("locale", .string(locale.tag)),
                    .test("returned", .null), .test("threw", .string(projected.0))]))
                throw error
            }
        }
    }

    // Development callback observation only. The lock protects every access;
    // callbacks run synchronously and are never invoked under this lock.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [JSONValue] = []
        func append(_ row: JSONValue) { lock.lock(); defer { lock.unlock() }; rows.append(row) }
        func reset() { lock.lock(); defer { lock.unlock() }; rows = [] }
        func calls() -> [JSONValue] { lock.lock(); defer { lock.unlock() }; return rows }
    }
    private final class NativeSentinel: Error, Sendable, CustomStringConvertible {
        let message: String
        init(_ message: String) { self.message = message }
        var description: String { message }
    }
    private struct NativeDisplay: PlaceholderConvertible {
        let recorder: Recorder
        func lokalizedDescription(maximumCharacters: Int?) throws -> String {
            recorder.append(.string("display")); return "caller"
        }
    }
}
