import XCTest
import Lokalized

final class CatalogModelTests: XCTestCase {
    func testClosedLanguageFormValuesCoverAllCanonicalForms() {
        XCTAssertEqual(LanguageFormValue.allValues.count, 61)
        XCTAssertEqual(Set(LanguageFormValue.allValues).count, 61)
        XCTAssertEqual(Set(LanguageFormValue.allValues.map(\.rawValue)).count, 61)
        for form in LanguageFormValue.allValues {
            XCTAssertEqual(LanguageFormValue(rawValue: form.rawValue), form)
            XCTAssertEqual(form.rawValue, "\(form.axis.rawValue)_\(form.displayName)")
            XCTAssertEqual(form.description, form.displayName)
        }
        XCTAssertEqual(LanguageFormValue(rawValue: "CASE_PREPOSITIONAL"), .grammaticalCase(.prepositional))
        XCTAssertEqual(LanguageFormValue(rawValue: "PHONETIC_H_ASPIRATED"), .phonetic(.hAspirated))
        XCTAssertNotEqual(LanguageFormValue.cardinality(.one), .ordinality(.one))
        XCTAssertNil(LanguageFormValue(rawValue: "ONE"))
        XCTAssertNil(LanguageFormValue(rawValue: "GENDER_masculine"))
        XCTAssertNil(LanguageFormValue(rawValue: "CUSTOM_FORM"))
    }

    func testLocalizedStringRequiresTranslationOrAtLeastOneAlternative() throws {
        XCTAssertThrowsError(try LocalizedString(key: "missing")) { error in
            XCTAssertEqual((error as? CatalogModelError)?.reason, .missingTranslationOrAlternative(key: "missing"))
            XCTAssertEqual(String(describing: error), "You must provide either a translation or at least one alternative expression. Offending key was 'missing'")
        }
        XCTAssertThrowsError(try LocalizedString(key: "missing", commentary: "notes",
                                                placeholderDefinitions: ["p": .expression(.init(translation: "fragment"))]))
        let empty = try LocalizedString(key: "", translation: "", commentary: "")
        XCTAssertEqual(empty.key, "")
        XCTAssertEqual(empty.translation, "")
        XCTAssertEqual(empty.commentary, "")
        XCTAssertTrue(empty.placeholderDefinitions.isEmpty)
        XCTAssertTrue(empty.alternatives.isEmpty)

        let alternative = try LocalizedString(key: "count == 1", translation: "one")
        let alternativesOnly = try LocalizedString(key: "message", alternatives: [alternative])
        XCTAssertNil(alternativesOnly.translation)
        XCTAssertEqual(alternativesOnly.alternatives, [alternative])
    }

    func testExpressionFragmentConstructorsPreserveTranslationOnlyAndOrderedModes() throws {
        let translationOnly = ExpressionTranslation(translation: "")
        XCTAssertEqual(translationOnly.translation, "")
        XCTAssertTrue(translationOnly.alternatives.isEmpty)
        XCTAssertThrowsError(try ExpressionTranslation(translation: "", alternatives: [])) { error in
            XCTAssertEqual((error as? CatalogModelError)?.reason, .emptyExpressionAlternatives)
            XCTAssertEqual(String(describing: error), "alternatives must not be empty; use ExpressionTranslation(String) for a translation-only fragment")
        }

        let first = ExpressionAlternative(expression: "count > 0", translation: "positive")
        let second = ExpressionAlternative(expression: "count > 0", translation: "also positive")
        let ordered = try ExpressionTranslation(translation: "default", alternatives: [first, second])
        let reversed = try ExpressionTranslation(translation: "default", alternatives: [second, first])
        XCTAssertEqual(ordered.alternatives, [first, second])
        XCTAssertNotEqual(ordered, reversed)
        XCTAssertEqual(ExpressionAlternative(expression: "", translation: "").expression, "")
    }

    func testConstructorsDeferCatalogSchemaAndExpressionValidation() throws {
        let mixed = LanguageFormTranslation(value: "not a valid identifier", translationsByLanguageForm: [
            .gender(.masculine): "{{ malformed placeholder }}",
            .cardinality(.one): "one",
        ])
        XCTAssertEqual(mixed.translationsByLanguageForm.count, 2)
        XCTAssertEqual(mixed.value, "not a valid identifier")
        XCTAssertNil(mixed.range)

        let range = LanguageFormTranslationRange(start: "", end: "not a valid identifier")
        let nonCardinalRange = LanguageFormTranslation(range: range, translationsByLanguageForm: [.gender(.neuter): "word"])
        XCTAssertNil(nonCardinalRange.value)
        XCTAssertEqual(nonCardinalRange.range, range)
        let empty = LanguageFormTranslation(value: "", translationsByLanguageForm: [:])
        XCTAssertTrue(empty.translationsByLanguageForm.isEmpty)

        let expression = try ExpressionTranslation(translation: "{{ bad placeholder }}", alternatives: [
            ExpressionAlternative(expression: "invalid syntax !!!", translation: "fragment"),
        ])
        let alternative = try LocalizedString(key: "invalid syntax !!!", translation: "{{ bad placeholder }}")
        let model = try LocalizedString(key: "entry", translation: "{{ bad placeholder }}",
                                       placeholderDefinitions: ["GENDER_MASCULINE": .languageForm(mixed),
                                                                "invalid placeholder": .languageForm(nonCardinalRange),
                                                                "fragment": .expression(expression)],
                                       alternatives: [alternative])
        XCTAssertEqual(model.placeholderDefinitions.count, 3)
        XCTAssertEqual(model.alternatives, [alternative])
    }

    func testAllUserTextParticipatesInExactUTF16EqualityAndHashing() throws {
        try assertExactDifference { try LocalizedString(key: ExactString($0), translation: "text") }
        try assertExactDifference { try LocalizedString(key: "entry", translation: $0) }
        try assertExactDifference { try LocalizedString(key: "entry", translation: "text", commentary: $0) }
        try assertExactDifference { try LocalizedString(key: "entry", translation: "text",
                                                        placeholderDefinitions: [ExactString($0): .expression(.init(translation: "fragment"))]) }
        try assertExactDifference { text in
            let alternative = try LocalizedString(key: ExactString(text), translation: "text")
            return try LocalizedString(key: "entry", alternatives: [alternative])
        }
        try assertExactDifference { LanguageFormTranslation(value: ExactString($0), translationsByLanguageForm: [.gender(.neuter): "text"]) }
        try assertExactDifference { LanguageFormTranslation(value: "input", translationsByLanguageForm: [.gender(.neuter): $0]) }
        try assertExactDifference { LanguageFormTranslationRange(start: ExactString($0), end: "end") }
        try assertExactDifference { LanguageFormTranslationRange(start: "start", end: ExactString($0)) }
        try assertExactDifference { ExpressionTranslation(translation: $0) }
        try assertExactDifference { ExpressionAlternative(expression: ExactString($0), translation: "text") }
        try assertExactDifference { ExpressionAlternative(expression: "count == 1", translation: $0) }
        try assertExactDifference { CatalogModelError(reason: .missingTranslationOrAlternative(key: ExactString($0))) }
    }

    func testCanonicalEquivalentPlaceholderKeysCoexist() throws {
        let composed = ExactString("\u{00E9}")
        let decomposed = ExactString("e\u{0301}")
        let model = try LocalizedString(key: "entry", translation: "text", placeholderDefinitions: [
            composed: .expression(.init(translation: "first")),
            decomposed: .expression(.init(translation: "second")),
        ])
        XCTAssertEqual(model.placeholderDefinitions.count, 2)
        XCTAssertEqual(model.placeholderDefinitions[composed], .expression(.init(translation: "first")))
        XCTAssertEqual(model.placeholderDefinitions[decomposed], .expression(.init(translation: "second")))
    }

    func testCollectionValueSemanticsPreserveModelWhenCallersMutateInputs() throws {
        var formTranslations: [LanguageFormValue: String] = [.cardinality(.one): "book"]
        let form = LanguageFormTranslation(value: "count", translationsByLanguageForm: formTranslations)
        formTranslations[.cardinality(.one)] = "changed"
        formTranslations[.cardinality(.other)] = "books"
        XCTAssertEqual(form.translationsByLanguageForm, [.cardinality(.one): "book"])

        let first = ExpressionAlternative(expression: "count == 1", translation: "one")
        var expressionAlternatives = [first]
        let expression = try ExpressionTranslation(translation: "other", alternatives: expressionAlternatives)
        expressionAlternatives.removeAll()
        XCTAssertEqual(expression.alternatives, [first])

        var placeholders: [ExactString: PlaceholderDefinition] = ["label": .languageForm(form)]
        let alternative = try LocalizedString(key: "count == 1", translation: "one")
        var alternatives = [alternative]
        let localized = try LocalizedString(key: "entry", translation: "text",
                                           placeholderDefinitions: placeholders, alternatives: alternatives)
        placeholders["label"] = .expression(expression)
        alternatives.removeAll()
        XCTAssertEqual(localized.placeholderDefinitions["label"], .languageForm(form))
        XCTAssertEqual(localized.alternatives, [alternative])
        var returned = localized.placeholderDefinitions
        returned.removeAll()
        XCTAssertEqual(localized.placeholderDefinitions.count, 1)
    }

    func testMapEqualityAndHashingIgnoreInsertionOrderButAlternativesKeepOrder() throws {
        var firstForms: [LanguageFormValue: String] = [:]
        firstForms[.cardinality(.one)] = "book"
        firstForms[.cardinality(.other)] = "books"
        var secondForms: [LanguageFormValue: String] = [:]
        secondForms[.cardinality(.other)] = "books"
        secondForms[.cardinality(.one)] = "book"
        let firstForm = LanguageFormTranslation(value: "count", translationsByLanguageForm: firstForms)
        let secondForm = LanguageFormTranslation(value: "count", translationsByLanguageForm: secondForms)
        XCTAssertEqual(firstForm, secondForm)
        XCTAssertEqual(firstForm.hashValue, secondForm.hashValue)

        var firstDefinitions: [ExactString: PlaceholderDefinition] = [:]
        firstDefinitions["books"] = .languageForm(firstForm)
        firstDefinitions["summary"] = .expression(.init(translation: "{{books}}"))
        var secondDefinitions: [ExactString: PlaceholderDefinition] = [:]
        secondDefinitions["summary"] = .expression(.init(translation: "{{books}}"))
        secondDefinitions["books"] = .languageForm(secondForm)
        let first = try LocalizedString(key: "entry", translation: "text", placeholderDefinitions: firstDefinitions)
        let second = try LocalizedString(key: "entry", translation: "text", placeholderDefinitions: secondDefinitions)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)

        let one = try LocalizedString(key: "count == 1", translation: "one")
        let many = try LocalizedString(key: "count > 1", translation: "many")
        XCTAssertNotEqual(try LocalizedString(key: "entry", alternatives: [one, many]),
                          try LocalizedString(key: "entry", alternatives: [many, one]))
    }

    func testAbsentAndEmptyOptionalTextStayDistinct() throws {
        let child = try LocalizedString(key: "count == 1", translation: "one")
        let absent = try LocalizedString(key: "entry", alternatives: [child])
        let empty = try LocalizedString(key: "entry", translation: "", alternatives: [child])
        XCTAssertNotEqual(absent, empty)
        XCTAssertNotEqual(try LocalizedString(key: "entry", translation: "text"),
                          try LocalizedString(key: "entry", translation: "text", commentary: ""))
    }

    func testEqualityAndHashingHandleDeepUnvalidatedAlternativeTreesIteratively() throws {
        var first = try LocalizedString(key: "count == 1", translation: "leaf")
        var second = try LocalizedString(key: "count == 1", translation: "leaf")
        var different = try LocalizedString(key: "count == 1", translation: "different leaf")
        for _ in 0..<5_000 {
            first = try LocalizedString(key: "count == 1", alternatives: [first])
            second = try LocalizedString(key: "count == 1", alternatives: [second])
            different = try LocalizedString(key: "count == 1", alternatives: [different])
        }
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
        XCTAssertFalse(first == different)
    }

    func testEqualityAndHashingMemoizeSharedAlternativeSubtrees() throws {
        var first = try LocalizedString(key: "count == 1", translation: "leaf")
        var second = try LocalizedString(key: "count == 1", translation: "leaf")
        for _ in 0..<120 {
            first = try LocalizedString(key: "count == 1", alternatives: [first, first])
            second = try LocalizedString(key: "count == 1", alternatives: [second, second])
        }
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)

        let leaf = try LocalizedString(key: "count == 1", translation: "leaf")
        let shared = try LocalizedString(key: "entry", alternatives: [leaf, leaf])
        let duplicated = try LocalizedString(key: "entry", alternatives: [
            LocalizedString(key: "count == 1", translation: "leaf"),
            LocalizedString(key: "count == 1", translation: "leaf"),
        ])
        XCTAssertEqual(shared, duplicated)
        XCTAssertEqual(shared.hashValue, duplicated.hashValue)
    }

    func testCatalogModelValuesHaveCheckedSendableConformance() {
        func requireSendable<Value: Sendable>(_ type: Value.Type) {}
        requireSendable(LocalizedString.self)
        requireSendable(PlaceholderDefinition.self)
        requireSendable(LanguageFormTranslation.self)
        requireSendable(LanguageFormTranslation.Selector.self)
        requireSendable(LanguageFormTranslationRange.self)
        requireSendable(ExpressionTranslation.self)
        requireSendable(ExpressionAlternative.self)
        requireSendable(LanguageFormValue.self)
        requireSendable(CatalogModelError.self)
        requireSendable(CatalogModelError.Reason.self)
    }

    private func assertExactDifference<Value: Hashable>(
        _ make: (String) throws -> Value, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let composed = try make("\u{00E9}")
        let decomposed = try make("e\u{0301}")
        XCTAssertNotEqual(composed, decomposed, file: file, line: line)
        XCTAssertEqual(Set([composed, decomposed]).count, 2, file: file, line: line)
        XCTAssertEqual(composed, try make("\u{00E9}"), file: file, line: line)
        XCTAssertEqual(composed.hashValue, try make("\u{00E9}").hashValue, file: file, line: line)
    }
}
