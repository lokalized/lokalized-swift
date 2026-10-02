import Foundation
import Lokalized

/// Standalone qualification of implemented M1 public catalog APIs.
/// No XCTest, sibling repositories, or reference fixtures are required.
enum CatalogQualification {
    static func run() throws -> Int {
        var checks = 0
        func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { throw ConformanceError("Catalog qualification: \(message)") }
            checks += 1
        }
        func refusal(_ message: String, _ body: () throws -> Void) throws -> StringsParseError {
            do { try body() }
            catch let error as StringsParseError { checks += 1; return error }
            throw ConformanceError("Catalog qualification accepted invalid input: \(message)")
        }

        let exactSource = #"{"é":"é","e\u0301":"e\u0301","__proto__":"safe","constructor":"safe","branch":{"alternatives":[{"count == 1":"one"}]}}"#
        let stringFile = try LocalizedStringLoader.parse(exactSource, locale: "en-us", source: "exact")
        let dataFile = try LocalizedStringLoader.parse(Data(exactSource.utf8), locale: "en-US", source: "exact")
        try expect(stringFile.locale == "en-US", "catalog locale casing")
        try expect(stringFile.strings == dataFile.strings, "String and Data produce equal complete models")
        try expect(stringFile.strings.count == 5 && Set(stringFile.strings.map(\.key)).count == 5,
                   "canonical-equivalent and hostile object keys remain distinct")
        try expect(stringFile.strings[0].translation.map { ExactString($0) } == ExactString("\u{00E9}"),
                   "composed translation spelling")
        try expect(stringFile.strings[1].translation.map { ExactString($0) } == ExactString("e\u{0301}"),
                   "decomposed translation spelling")
        try expect(stringFile.strings.last?.translation == nil && stringFile.strings.last?.alternatives.count == 1,
                   "alternatives-only entry stays absent rather than empty")
        try expect(stringFile.originsByKey[ExactString("e\u{0301}")] == ["exact"], "exact-key origin lookup")
        let defined = try LocalizedStringLoader.defineCatalog(stringFile.strings, locale: "en-US", source: "defined")
        try expect(defined.strings == stringFile.strings, "typed definitions retain every parsed model field")

        let escaped = try LocalizedStringLoader.parse(#"{"A":"\\{{not a name}} \\}} {{é}}"}"#, locale: "en")
        try expect(escaped.strings.count == 1, "escaped delimiters and Unicode placeholders")
        let supplementary = try refusal("UTF-16 delimiter index") {
            _ = try LocalizedStringLoader.parse(#"{"A":"😀}}́"}"#, locale: "en", source: "utf16")
        }
        try expect(supplementary.message.hasSuffix("Unexpected placeholder closing delimiter '}}' at index 2"),
                   "delimiter error offsets count UTF-16")
        let duplicate = try refusal("duplicate prescan priority") {
            _ = try LocalizedStringLoader.parse(#"{"A":{"unexpected":1,"translation":"x","translation":"y"}}"#,
                                              locale: "en", source: "duplicate")
        }
        try expect(duplicate.path == "$.A" && duplicate.message.contains("duplicate JSON object member 'translation'"),
                   "duplicate member precedes schema errors within its root")

        let dataLimits = try LocalizedStringLoadingOptions(maximumInputBytes: 2, maximumReaderCharacters: 1,
                                                          maximumJsonNestingDepth: 1, maximumTotalInputBytes: 2,
                                                          maximumTranslationNodes: 0)
        try expect(try LocalizedStringLoader.parse(Data("{}".utf8), locale: "en", loadingOptions: dataLimits).strings.isEmpty,
                   "Data ignores reader-character limits at the exact byte boundary")
        let readerFailure = try refusal("reader boundary") {
            _ = try LocalizedStringLoader.parse("{}", locale: "en", source: "reader", loadingOptions: dataLimits)
        }
        try expect(readerFailure.message.contains("maximum size of 1 characters"), "String enforces reader limits")
        let readerLimits = try LocalizedStringLoadingOptions(maximumInputBytes: 1, maximumReaderCharacters: 2,
                                                            maximumTotalInputBytes: 1, maximumTranslationNodes: 0)
        try expect(try LocalizedStringLoader.parse("{}", locale: "en", loadingOptions: readerLimits).strings.isEmpty,
                   "String does not fabricate an input-byte charge")
        let bomFailure = try refusal("BOM counts toward reader budget") {
            _ = try LocalizedStringLoader.parse("\u{FEFF}{}", locale: "en", loadingOptions: readerLimits)
        }
        try expect(bomFailure.message.contains("maximum size of 2 characters"), "BOM is counted before removal")
        try expect(try LocalizedStringLoader.parse("\u{FEFF}{}", locale: "en").strings.isEmpty, "one leading BOM is accepted")
        let extraBOM = try refusal("second BOM") {
            _ = try LocalizedStringLoader.parse(Data("\u{FEFF}\u{FEFF}{}".utf8), locale: "en", source: "bom")
        }
        try expect(extraBOM.line == 1 && extraBOM.column == 1 && extraBOM.cause != nil, "second BOM retains lexical location/cause")
        let utf8 = try refusal("strict UTF-8") {
            _ = try LocalizedStringLoader.parse(Data([0xC0, 0x80]), locale: "en", source: "bytes")
        }
        try expect(utf8.message == "bytes: localized strings resource is not valid UTF-8" && utf8.cause != nil,
                   "invalid UTF-8 retains source and decoding cause")
        let bytePriority = try refusal("aggregate byte priority") {
            _ = try LocalizedStringLoader.parse(Data("abcde".utf8), locale: "en", source: "priority",
                                              loadingOptions: .init(maximumInputBytes: 4, maximumTotalInputBytes: 3))
        }
        try expect(bytePriority.message.contains("aggregate maximum of 3 input bytes"), "aggregate bytes precede per-file refusal")
        let nodePriority = try refusal("root node budget priority") {
            _ = try LocalizedStringLoader.parse(#"{"A":null,"B":"b"}"#, locale: "en", source: "nodes",
                                              loadingOptions: .init(maximumTranslationNodes: 1))
        }
        try expect(nodePriority.message.contains("aggregate maximum of 1 translation nodes"), "root batch budget precedes root schema")
        let rawDepth = try refusal("raw JSON depth") {
            _ = try LocalizedStringLoader.parse(#"{"A":{"translation":"a"}}"#, locale: "en",
                                              loadingOptions: .init(maximumJsonNestingDepth: 1))
        }
        try expect(rawDepth.message.contains("JSON nesting depth exceeds the maximum of 1"), "raw JSON nesting limit")
        let rawIndependent = try LocalizedStringLoadingOptions(maximumInputBytes: 1, maximumReaderCharacters: 1,
                                                              maximumJsonNestingDepth: 1, maximumTotalInputBytes: 1)
        try expect(try LocalizedStringLoader.defineCatalog(stringFile.strings, locale: "en", loadingOptions: rawIndependent).strings.count == 5,
                   "typed models do not inherit raw byte, character, or JSON-depth budgets")

        let shardA = try LocalizedStringLoader.parse(#"{"A":{"translation":"text","commentary":"note"}}"#,
                                                   locale: "en-US", source: "\u{00E9}")
        let shardB = try LocalizedStringLoader.parse(#"{"A":{"commentary":"note","translation":"text"}}"#,
                                                   locale: "en-us", source: "e\u{0301}")
        let merged = try LocalizedStringLoader.mergeParsedStringsFiles([shardA, shardB],
                                                                      loadingOptions: .init(maximumTranslationNodes: 1))
        try expect(merged.strings.count == 1 && merged.sources.count == 2, "equal shards deduplicate before the node budget")
        try expect(merged.originsByKey["A"]?.map { ExactString($0) } == [ExactString("\u{00E9}"), ExactString("e\u{0301}")],
                   "canonical-equivalent source names remain distinct origins")
        let conflict = try LocalizedStringLoader.parse(#"{"A":{"translation":"text","commentary":"different"}}"#,
                                                     locale: "en-US", source: "conflict")
        let conflictError = try refusal("conflicting complete definition") {
            _ = try LocalizedStringLoader.mergeParsedStringsFiles([shardA, conflict])
        }
        try expect(conflictError.message.contains("defined differently"), "commentary participates in merge equality")
        let otherLocale = try LocalizedStringLoader.parse("{}", locale: "en-GB", source: "other")
        let localeError = try refusal("exact shard locale") {
            _ = try LocalizedStringLoader.mergeParsedStringsFiles([shardA, otherLocale])
        }
        try expect(localeError.message.contains("one exact locale"), "same-language locales cannot merge")
        let fileLimit = try refusal("merge file budget") {
            _ = try LocalizedStringLoader.mergeParsedStringsFiles([shardA, shardB],
                                                                  loadingOptions: .init(maximumLocalizedStringsFiles: 1))
        }
        try expect(fileLimit.message.contains("file limit of 1"), "merge counts each supplied shard")

        let warningSource = #"{"A":{"translation":"{{label}}","placeholders":{"label":{"value":"count","translations":{"CARDINALITY_ONE":"one"}}}}}"#
        let warnings = try LocalizedStringLoader.parse(warningSource, locale: "ru", source: "warning")
        try expect(warnings.warnings.count == 1, "incomplete cardinality is a warning")
        try expect(warnings.warnings[0].missingLanguageForms == ["CARDINALITY_FEW", "CARDINALITY_MANY", "CARDINALITY_OTHER"],
                   "warning forms retain enum order")
        let recorder = CatalogQualificationWarnings()
        let marker = CatalogQualificationWarningStop()
        do {
            _ = try LocalizedStringLoader.parse(warningSource, locale: "ru", warningHandler: { warning in
                recorder.append(warning)
                let nested = try LocalizedStringLoader.parse("{}", locale: "en", source: "reentry")
                guard nested.strings.isEmpty else { throw ConformanceError("Warning-handler reentry returned a nonempty catalog") }
                throw marker
            })
            throw ConformanceError("Catalog qualification swallowed warning-handler error")
        } catch {
            try expect((error as? CatalogQualificationWarningStop) === marker, "warning-handler error identity survives reentry")
        }
        try expect(recorder.values.count == 1, "warning-handler reentry uses an independent session")
        let refusedRecorder = CatalogQualificationWarnings()
        let warningLimit = try refusal("warning budget before delivery") {
            _ = try LocalizedStringLoader.parse(warningSource, locale: "ru",
                                              warningHandler: { refusedRecorder.append($0) },
                                              loadingOptions: .init(maximumWarnings: 0))
        }
        try expect(warningLimit.message.contains("aggregate maximum of 0 warnings") && refusedRecorder.values.isEmpty,
                   "a refused warning is never delivered")
        let lateRecorder = CatalogQualificationWarnings()
        let lateSource = String(warningSource.dropLast()) + #", "B": null}"#
        _ = try refusal("warnings precede a later root refusal") {
            _ = try LocalizedStringLoader.parse(lateSource, locale: "ru", warningHandler: { lateRecorder.append($0) })
        }
        try expect(lateRecorder.values.count == 1, "earlier root warning is delivered before a later schema failure")
        let warningMerge = try LocalizedStringLoader.mergeParsedStringsFiles([warnings, warnings])
        try expect(warningMerge.strings.count == 1 && warningMerge.warnings.count == 2,
                   "merge carries original warnings without recomputing them")
        _ = try refusal("carried warning budget") {
            _ = try LocalizedStringLoader.mergeParsedStringsFiles([warnings, warnings],
                                                                  loadingOptions: .init(maximumWarnings: 1))
        }

        func expressionCatalog(_ expression: String) -> String {
            "{\"A\":{\"alternatives\":[{\"\(expression)\":\"one\"}]}}"
        }
        let base = "n == 1"
        let atCeiling = String(repeating: " ", count: TranslationRuntimeLimits.hardMaximumExpressionCharacters - base.utf16.count) + base
        try expect(try LocalizedStringLoader.parse(expressionCatalog(atCeiling), locale: "en").strings.count == 1,
                   "loader accepts the hard character ceiling above runtime defaults")
        let sourceLimit = try refusal("hard expression character ceiling") {
            _ = try LocalizedStringLoader.parse(expressionCatalog(" " + atCeiling), locale: "en")
        }
        try expect(sourceLimit.message.contains("Expression length 4097 exceeds maximum supported length 4096") && sourceLimit.cause != nil,
                   "expression ceiling refusal retains the compilation cause")
        let underTokens = Array(repeating: base, count: 128).joined(separator: " || ")
        try expect(try LocalizedStringLoader.parse(expressionCatalog(underTokens), locale: "en").strings.count == 1,
                   "loader accepts 511 tokens above the runtime token default")
        let tokenLimit = try refusal("hard expression token ceiling") {
            _ = try LocalizedStringLoader.parse(expressionCatalog(underTokens + " || " + base), locale: "en")
        }
        try expect(tokenLimit.message.contains("exceeds maximum supported token count 512"), "hard token ceiling")
        let atDepth = String(repeating: "(", count: 64) + base + String(repeating: ")", count: 64)
        try expect(try LocalizedStringLoader.parse(expressionCatalog(atDepth), locale: "en").strings.count == 1,
                   "loader accepts grouping depth 64 above runtime defaults")
        let expressionDepth = try refusal("hard expression grouping ceiling") {
            _ = try LocalizedStringLoader.parse(expressionCatalog("(" + atDepth + ")"), locale: "en")
        }
        try expect(expressionDepth.message.contains("maximum supported depth 64"), "hard grouping ceiling")
        try expect(try LocalizedStringLoader.parse(expressionCatalog("n == 1e-4096"), locale: "en").strings.count == 1,
                   "numeric literals use hard scale limits at load time")
        let numberScale = try refusal("hard numeric scale ceiling") {
            _ = try LocalizedStringLoader.parse(expressionCatalog("n == 1e-4097"), locale: "en")
        }
        try expect(numberScale.message.contains("maximum absolute scale of 4096"), "numeric literal hard scale refusal")

        let leaf = try LocalizedString(key: "count == 1", translation: "{{label}}",
                                       placeholderDefinitions: ["label": .languageForm(.init(value: "count", translationsByLanguageForm: [.cardinality(.one): "one"]))])
        var shared = leaf
        for _ in 0..<120 { shared = try LocalizedString(key: "count == 1", alternatives: [shared, shared]) }
        let sharedFile = try LocalizedStringLoader.defineCatalog([shared], locale: "ru", source: "shared")
        try expect(sharedFile.strings.count == 1 && sharedFile.warnings.count == 1,
                   "shared DAG validation and per-root warnings remain linear")
        let sharedBudget = try refusal("shared DAG budget admission") {
            _ = try LocalizedStringLoader.defineCatalog([shared], locale: "ru", source: "shared",
                                                       loadingOptions: .init(maximumTranslationNodes: 32))
        }
        try expect(sharedBudget.message.contains("aggregate maximum of 32 translation nodes"), "shared DAG refuses a small model budget promptly")
        let firstRoot = try LocalizedString(key: "first", alternatives: [shared])
        let secondRoot = try LocalizedString(key: "second", alternatives: [shared])
        let twoRoots = try LocalizedStringLoader.defineCatalog([firstRoot, secondRoot], locale: "ru")
        try expect(twoRoots.warnings.map(\.key) == [ExactString("first"), ExactString("second")],
                   "shared subtrees warn once for each distinct root")
        var tail = try LocalizedString(key: ExactString(base), translation: "leaf")
        for _ in 0..<8 { tail = try LocalizedString(key: ExactString(base), alternatives: [tail]) }
        let shallow = try LocalizedString(key: "shallow", alternatives: [tail])
        var deep = tail
        for _ in 0..<120 { deep = try LocalizedString(key: ExactString(base), alternatives: [deep]) }
        let tooDeep = try LocalizedString(key: "deep", alternatives: [deep])
        let placement = try refusal("deeper reuse must revalidate depth") {
            _ = try LocalizedStringLoader.defineCatalog([shallow, tooDeep], locale: "en")
        }
        try expect(placement.message.contains("alternative nesting exceeds the maximum depth of 128"),
                   "memoized shallow validation cannot prove a deeper placement")
        return checks
    }
}

private final class CatalogQualificationWarningStop: Error, Sendable {}

/// Mutable test observations are protected because handlers are Sendable.
private final class CatalogQualificationWarnings: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [LocalizedStringWarning] = []
    var values: [LocalizedStringWarning] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
    func append(_ warning: LocalizedStringWarning) {
        lock.lock(); defer { lock.unlock() }
        stored.append(warning)
    }
}
