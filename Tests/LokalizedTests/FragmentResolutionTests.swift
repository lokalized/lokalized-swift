import XCTest
@testable import Lokalized
@testable import LokalizedConformanceSupport

final class FragmentResolutionTests: XCTestCase {
    private func kernel(_ text: String, locale: String = "en", limits: TranslationRuntimeLimits = .defaults,
                        resolver: PhoneticResolver? = nil) throws -> CompiledCatalogResolution {
        try .init(LocalizedStringLoader.parse(text, locale: locale), locale: LocaleTag(locale),
                  runtimeLimits: limits, phoneticResolver: resolver)
    }
    private func rendered(_ engine: CompiledCatalogResolution, key: ExactString = "k",
                          values: [ExactString: PlaceholderValue] = [:]) throws -> String {
        guard case .translation(let text, _) = try engine.resolve(key, placeholders: values) else {
            throw ConformanceError("Expected a component translation")
        }
        return text
    }
    private func evaluationFailure(_ action: () throws -> Void) throws -> TranslationEvaluationError {
        do { try action() }
        catch let error as TranslationEvaluationError { return error }
        throw ConformanceError("Expected categorized evaluation failure")
    }

    func testNativeStandaloneFragmentQualification() throws {
        XCTAssertGreaterThan(try ConformanceRunner.fragmentSelfTest(), 50)
    }

    func testAllTenLanguageFormAxesSelectExactlyTaggedValues() throws {
        let forms: [LanguageFormValue] = [.cardinality(.one), .ordinality(.two), .gender(.feminine),
            .grammaticalCase(.accusative), .definiteness(.definite), .classifier(.person),
            .formality(.formal), .clusivity(.inclusive), .animacy(.animate), .phonetic(.vowel)]
        for form in forms {
            let model = try LocalizedString(key: "k", translation: "{{fragment}}", placeholderDefinitions: [
                "fragment": .languageForm(.init(value: "value", translationsByLanguageForm: [form: form.rawValue]))
            ])
            let catalog = try LocalizedStringLoader.defineCatalog([model], locale: "en")
            let engine = try CompiledCatalogResolution(catalog, locale: LocaleTag("en"))
            XCTAssertEqual(try rendered(engine, values: ["value": .languageForm(form)]), form.rawValue)
        }
    }

    func testScopeReplacementCanChangePlaceholderKind() throws {
        let engine = try kernel(#"{"k":{"translation":"root","placeholders":{"p":{"value":"g","translations":{"GENDER_MASCULINE":"root"}}},"alternatives":[{"selected == 1":{"translation":"{{p}}","placeholders":{"p":{"translation":"expression-child"}}}}]}}"#)
        XCTAssertEqual(try rendered(engine, values: ["selected": .integer(1)]), "expression-child")
    }

    func testFragmentFirstMatchDoesNotReadLaterPredicate() throws {
        let engine = try kernel(#"{"k":{"translation":"{{p}}","placeholders":{"p":{"translation":"default","alternatives":[{"selected == 1":"first"},{"absent == 1":"later"}]}}}}"#)
        XCTAssertEqual(try rendered(engine, values: ["selected": .integer(1)]), "first")
    }

    func testSelectionsFinishInBreadthFirstAppearanceOrder() throws {
        let engine = try kernel(#"{"k":{"translation":"{{z}} {{a}}","placeholders":{"z":{"translation":"{{nested}}"},"a":{"value":"missingA","translations":{"GENDER_MASCULINE":"a"}},"nested":{"value":"missingNested","translations":{"GENDER_MASCULINE":"nested"}}}}}"#)
        let failure = try evaluationFailure { _ = try rendered(engine) }
        XCTAssertTrue(failure.message.contains("generated placeholder 'a'"))
        XCTAssertTrue(failure.message.contains("Missing value for placeholder 'missingA'"))
        XCTAssertFalse(failure.message.contains("missingNested"))
    }

    func testScopeFailureNamesAncestorDeclaringPath() throws {
        let engine = try kernel(#"{"k":{"translation":"root","placeholders":{"p":{"translation":"{{missing}}"}},"alternatives":[{"selected == 1":{"translation":"{{p}}"}}]}}"#)
        let failure = try evaluationFailure { _ = try rendered(engine, values: ["selected": .integer(1)]) }
        XCTAssertEqual(failure.message, "Unable to resolve generated placeholder 'p' (ExpressionTranslation) for key 'k'; definition declared at k; selected default translation: Missing value for placeholder(s) [missing] in key 'k'")
        XCTAssertEqual((failure.cause as? TranslationEvaluationError)?.message, "Missing value for placeholder(s) [missing] in key 'k'")
    }

    func testAuthoredCompilationOrderSurvivesModelEqualityAndShardMerge() throws {
        let zFirst = try LocalizedStringLoader.parse(#"{"k":{"translation":"unused","placeholders":{"z":{"translation":"z","alternatives":[{"longZ == 1":"yes"}]},"a":{"translation":"a","alternatives":[{"longA == 1":"yes"}]}}}}"#, locale: "en", source: "z-first")
        let aFirst = try LocalizedStringLoader.parse(#"{"k":{"translation":"unused","placeholders":{"a":{"translation":"a","alternatives":[{"longA == 1":"yes"}]},"z":{"translation":"z","alternatives":[{"longZ == 1":"yes"}]}}}}"#, locale: "en", source: "a-first")
        XCTAssertEqual(zFirst.strings, aFirst.strings)
        XCTAssertEqual(Set(zFirst.strings + aFirst.strings).count, 1)
        XCTAssertEqual(zFirst.strings[0].placeholderDefinitionOrder, ["z", "a"])
        XCTAssertEqual(aFirst.strings[0].placeholderDefinitionOrder, ["a", "z"])
        let merged = try LocalizedStringLoader.mergeParsedStringsFiles([zFirst, aFirst])
        let failure = try evaluationFailure {
            _ = try CompiledCatalogResolution(merged, locale: LocaleTag("en"), runtimeLimits: TranslationRuntimeLimits(maximumExpressionCharacters: 4))
        }
        XCTAssertTrue(failure.message.contains("placeholder 'z'"))
        let native = try LocalizedString(key: "k", translation: zFirst.strings[0].translation,
                                        placeholderDefinitions: zFirst.strings[0].placeholderDefinitions)
        XCTAssertEqual(native, zFirst.strings[0])
        XCTAssertEqual(native.placeholderDefinitionOrder, ["a", "z"])
    }

    func testUnreachableFragmentStillCompilesAgainstInstanceLimits() throws {
        let failure = try evaluationFailure {
            _ = try kernel(#"{"k":{"translation":"plain","placeholders":{"unreached":{"translation":"default","alternatives":[{"longName == 1":"selected"}]}}}}"#, limits: TranslationRuntimeLimits(maximumExpressionCharacters: 4))
        }
        XCTAssertTrue(failure.message.contains("generated-fragment alternative 0"))
        XCTAssertTrue(failure.message.contains("placeholder 'unreached'"))
        XCTAssertEqual((failure.cause as? TranslationEvaluationError)?.message, "Expression length 13 exceeds maximum supported length 4")
    }

    func testPrebuiltOperandsRevalidateActiveSelectorLimits() throws {
        let operands = try PluralOperands(.integer(1), visibleDecimalPlaces: 2, compactExponent: 3)
        let engine = try kernel(#"{"k":{"translation":"{{p}}","placeholders":{"p":{"value":"count","translations":{"CARDINALITY_OTHER":"other"}}}}}"#, limits: TranslationRuntimeLimits(maximumVisibleDecimalPlaces: 1, maximumCompactExponent: 2))
        let failure = try evaluationFailure { _ = try rendered(engine, values: ["count": .pluralOperands(operands)]) }
        XCTAssertTrue(failure.message.contains("Placeholder compact exponent 3 exceeds the configured maximum of 2"))
        XCTAssertFalse(failure.message.contains("visible decimal places"))
    }

    func testExplicitPluralCategoryBypassesUnsupportedLocaleClassification() throws {
        let engine = try kernel(#"{"k":{"translation":"{{p}}","placeholders":{"p":{"value":"count","translations":{"CARDINALITY_ONE":"one"}}}}}"#, locale: "zz")
        XCTAssertEqual(try rendered(engine, values: ["count": .languageForm(.cardinality(.one))]), "one")
        XCTAssertThrowsError(try rendered(engine, values: ["count": .integer(1)])) { error in
            XCTAssertTrue(error is UnsupportedLocaleError)
        }
    }

    func testRepeatedCallerReplacementGetsRemainingBudgetAtEveryOccurrence() throws {
        let seen = FragmentRenderingRecorder()
        let engine = try kernel(#"{"k":"x{{a}}-{{a}}"}"#, limits: TranslationRuntimeLimits(maximumInterpolatedOutputCharacters: 6))
        let outcome = try engine.resolve("k", placeholders: ["a": .text("v")], callerValueRenderer: { _, value, remaining in
            seen.append(remaining)
            return try value.interpolationText(maximumCharacters: remaining)
        })
        guard case .translation(let text, _) = outcome else { return XCTFail("Expected rendered component") }
        XCTAssertEqual(text, "xv-v")
        XCTAssertEqual(seen.snapshot(), [5, 3])
    }

    func testGeneratedExpansionPrecedesCallerCustomRendering() throws {
        let seen = FragmentRenderingRecorder()
        let engine = try kernel(#"{"k":{"translation":"{{caller}} {{broken}}","placeholders":{"broken":{"translation":"{{absent}}"}}}}"#)
        XCTAssertThrowsError(try engine.resolve("k", placeholders: ["caller": .text("v")], callerValueRenderer: { _, _, remaining in
            seen.append(remaining); return "v"
        }))
        XCTAssertTrue(seen.snapshot().isEmpty)
    }

    func testSharedAlternativeGraphCompilesAndSelectsWithoutExpansion() throws {
        var graph = try LocalizedString(key: "enabled == 1", translation: "leaf")
        for _ in 0..<120 { graph = try LocalizedString(key: "enabled == 1", translation: "unselected", alternatives: [graph, graph]) }
        let catalog = try LocalizedStringLoader.defineCatalog([graph], locale: "en")
        let engine = try CompiledCatalogResolution(catalog, locale: LocaleTag("en"))
        XCTAssertEqual(try rendered(engine, key: "enabled == 1", values: ["enabled": .integer(1)]), "leaf")
    }

    func testConcurrentAttemptsDoNotShareGeneratedExpansionBudget() async throws {
        let engine = try kernel(#"{"k":{"translation":"{{p}}/{{p}}","placeholders":{"p":{"translation":"abc"}}}}"#, limits: TranslationRuntimeLimits(maximumGeneratedExpansionCharacters: 3))
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<40 {
                group.addTask {
                    guard case .translation(let text, _) = try engine.resolve("k", placeholders: [:]) else {
                        throw ConformanceError("Expected component rendering")
                    }
                    return text
                }
            }
            for try await value in group { XCTAssertEqual(value, "abc/abc") }
        }
    }
}

private final class FragmentRenderingRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []
    func append(_ value: Int) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    func snapshot() -> [Int] { lock.lock(); defer { lock.unlock() }; return values }
}
