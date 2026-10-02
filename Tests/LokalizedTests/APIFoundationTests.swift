import XCTest
@testable import Lokalized

final class APIFoundationTests: XCTestCase {
    func testAllLanguageFormsPreserveTokensDisplayNamesAndOrder() {
        XCTAssertEqual(LanguageFormAxis.allCases.map(\.rawValue), [
            "CARDINALITY", "ORDINALITY", "GENDER", "CASE", "DEFINITENESS",
            "CLASSIFIER", "FORMALITY", "CLUSIVITY", "ANIMACY", "PHONETIC",
        ])
        assertForms(Cardinality.self, axis: .cardinality,
                    names: ["ZERO", "ONE", "TWO", "FEW", "MANY", "OTHER"])
        assertForms(Ordinality.self, axis: .ordinality,
                    names: ["ZERO", "ONE", "TWO", "FEW", "MANY", "OTHER"])
        assertForms(Gender.self, axis: .gender,
                    names: ["MASCULINE", "FEMININE", "COMMON", "NEUTER"])
        assertForms(GrammaticalCase.self, axis: .grammaticalCase,
                    names: ["NOMINATIVE", "ACCUSATIVE", "GENITIVE", "DATIVE", "INSTRUMENTAL",
                            "LOCATIVE", "PREPOSITIONAL", "VOCATIVE", "ABLATIVE"])
        assertForms(Definiteness.self, axis: .definiteness,
                    names: ["DEFINITE", "INDEFINITE", "CONSTRUCT"])
        assertForms(Classifier.self, axis: .classifier,
                    names: ["GENERAL", "PERSON", "ANIMAL", "LONG_THIN", "FLAT", "BOUND", "MACHINE", "VEHICLE"])
        assertForms(Formality.self, axis: .formality,
                    names: ["CASUAL", "INFORMAL", "FORMAL", "HUMBLE", "HONORIFIC"])
        assertForms(Clusivity.self, axis: .clusivity, names: ["INCLUSIVE", "EXCLUSIVE"])
        assertForms(Animacy.self, axis: .animacy, names: ["ANIMATE", "INANIMATE"])
        assertForms(Phonetic.self, axis: .phonetic,
                    names: ["VOWEL", "CONSONANT", "H_SILENT", "H_ASPIRATED", "S_IMPURE", "Z", "GN", "PS", "PN",
                            "X", "GLIDE_Y", "GLIDE_W", "STRESSED_A", "SOLAR", "LUNAR", "OTHER"])

        let counts = [Cardinality.allCases.count, Ordinality.allCases.count, Gender.allCases.count,
                      GrammaticalCase.allCases.count, Definiteness.allCases.count, Classifier.allCases.count,
                      Formality.allCases.count, Clusivity.allCases.count, Animacy.allCases.count, Phonetic.allCases.count]
        XCTAssertEqual(counts, [6, 6, 4, 9, 3, 8, 5, 2, 2, 16])
        XCTAssertEqual(counts.reduce(0, +), 61)
        XCTAssertNil(Gender(rawValue: "masculine"))
        XCTAssertNil(Gender(rawValue: "MASCULINE"))
        XCTAssertNil(Cardinality(rawValue: "ORDINALITY_ONE"))
    }

    func testSettingsUseExistingSerializedSpellingsAndExplicitDisabledCases() {
        XCTAssertEqual(BidiIsolation.allCases.map(\.rawValue), ["none", "rtl-locales", "always"])
        XCTAssertEqual(LocaleMatchType.allCases.map(\.rawValue), [
            "none", "exact", "canonical", "cldr-fallback", "likely-subtag",
            "extended-range", "primary-language", "wildcard",
        ])
        let bidiOverride: BidiIsolation? = .disabled
        let match: LocaleMatchType? = .noMatch
        XCTAssertNotNil(bidiOverride)
        XCTAssertNotNil(match)
        XCTAssertNil(BidiIsolation(rawValue: "all"))
    }

    func testExactStringKeepsCanonicallyEquivalentKeysDistinct() {
        let composed = "\u{00E9}"
        let decomposed = "e\u{0301}"
        XCTAssertEqual(composed, decomposed) // Native equality would collapse these keys.

        let first = ExactString(composed)
        let second = ExactString(decomposed)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.utf16Count, 1)
        XCTAssertEqual(second.utf16Count, 2)
        XCTAssertEqual(Array(first.string.utf16), [0x00E9])
        XCTAssertEqual(Array(second.string.utf16), [0x0065, 0x0301])
        XCTAssertEqual(Set([first, second, ExactString(composed)]).count, 2)

        let catalog: [ExactString: Int] = [first: 1, second: 2]
        XCTAssertEqual(catalog[first], 1)
        XCTAssertEqual(catalog[second], 2)
    }

    func testExactStringUsesUTF16LengthOrderAndLiteralConversion() {
        let literal: ExactString = "\u{1F469}\u{200D}\u{1F4BB}"
        XCTAssertEqual(literal, ExactString("👩‍💻"))
        XCTAssertEqual(literal.string.count, 1)
        XCTAssertEqual(literal.utf16Count, 5)
        XCTAssertEqual(literal.description, literal.string)
        XCTAssertEqual(ExactString(""), "")
        XCTAssertEqual(ExactString("").utf16Count, 0)

        // A surrogate pair starts below U+E000 in unsigned UTF-16 order, despite
        // the represented supplementary scalar being numerically larger.
        XCTAssertLessThan(ExactString("\u{10000}"), ExactString("\u{E000}"))
        XCTAssertLessThan(ExactString("e\u{0301}"), ExactString("\u{00E9}"))
        XCTAssertEqual([ExactString("ab"), ExactString("a"), ExactString("")].sorted(), ["", "a", "ab"])
        XCTAssertNotEqual(ExactString("a\0b"), ExactString("ab"))
        XCTAssertEqual(ExactString("a\0b").utf16Count, 3)
    }

    func testRuntimeLimitDefaultsMatchJava() {
        XCTAssertEqual(limitValues(.defaults), [1_024, 1_024, 1_024, 64, 2_048, 256, 32, 32, 262_144, 1_048_576])
        XCTAssertEqual(TranslationRuntimeLimits(), .defaults)
    }

    func testRuntimeLimitMinimumAndHardCeilingValuesAreAccepted() throws {
        let minimum = try TranslationRuntimeLimits(
            maximumNumberPrecision: 1,
            maximumAbsoluteNumberScale: 0,
            maximumVisibleDecimalPlaces: 0,
            maximumCompactExponent: 0,
            maximumExpressionCharacters: 1,
            maximumExpressionTokens: 1,
            maximumExpressionNestingDepth: 0,
            maximumGeneratedPlaceholderDepth: 0,
            maximumInterpolatedOutputCharacters: 1,
            maximumGeneratedExpansionCharacters: 0
        )
        XCTAssertEqual(limitValues(minimum), [1, 0, 0, 0, 1, 1, 0, 0, 1, 0])

        let ceiling = try TranslationRuntimeLimits(
            maximumNumberPrecision: 4_096,
            maximumAbsoluteNumberScale: 4_096,
            maximumVisibleDecimalPlaces: 4_096,
            maximumCompactExponent: 4_096,
            maximumExpressionCharacters: 4_096,
            maximumExpressionTokens: 512,
            maximumExpressionNestingDepth: 64,
            maximumGeneratedPlaceholderDepth: 64,
            maximumInterpolatedOutputCharacters: 1_048_576,
            maximumGeneratedExpansionCharacters: 8_388_608
        )
        XCTAssertEqual(limitValues(ceiling), [4_096, 4_096, 4_096, 4_096, 4_096, 512, 64, 64, 1_048_576, 8_388_608])
    }

    func testEveryRuntimeLimitRejectsOutOfRangeValuesInsteadOfClamping() {
        typealias LimitCase = (parameter: String, range: ClosedRange<Int>, make: (Int) throws -> TranslationRuntimeLimits)
        let cases: [LimitCase] = [
            ("maximumNumberPrecision", 1...4_096, { try .init(maximumNumberPrecision: $0) }),
            ("maximumAbsoluteNumberScale", 0...4_096, { try .init(maximumAbsoluteNumberScale: $0) }),
            ("maximumVisibleDecimalPlaces", 0...4_096, { try .init(maximumVisibleDecimalPlaces: $0) }),
            ("maximumCompactExponent", 0...4_096, { try .init(maximumCompactExponent: $0) }),
            ("maximumExpressionCharacters", 1...4_096, { try .init(maximumExpressionCharacters: $0) }),
            ("maximumExpressionTokens", 1...512, { try .init(maximumExpressionTokens: $0) }),
            ("maximumExpressionNestingDepth", 0...64, { try .init(maximumExpressionNestingDepth: $0) }),
            ("maximumGeneratedPlaceholderDepth", 0...64, { try .init(maximumGeneratedPlaceholderDepth: $0) }),
            ("maximumInterpolatedOutputCharacters", 1...1_048_576, { try .init(maximumInterpolatedOutputCharacters: $0) }),
            ("maximumGeneratedExpansionCharacters", 0...8_388_608, { try .init(maximumGeneratedExpansionCharacters: $0) }),
        ]
        for entry in cases {
            for invalid in [entry.range.lowerBound - 1, entry.range.upperBound + 1, Int.min, Int.max] {
                XCTAssertThrowsError(try entry.make(invalid), entry.parameter) { error in
                    guard let validation = error as? TranslationRuntimeLimits.ValidationError else {
                        return XCTFail("Unexpected error type: \(error)")
                    }
                    XCTAssertEqual(validation.parameter, entry.parameter)
                    XCTAssertEqual(validation.value, invalid)
                    XCTAssertEqual(validation.allowedRange, entry.range)
                }
            }
        }
    }

    func testRuntimeLimitsKeepOmittedDefaultsAndReportFirstInvalidParameter() throws {
        let customized = try TranslationRuntimeLimits(maximumCompactExponent: 2_048)
        var expected = limitValues(.defaults)
        expected[3] = 2_048
        XCTAssertEqual(limitValues(customized), expected)

        XCTAssertThrowsError(try TranslationRuntimeLimits(maximumNumberPrecision: 0, maximumAbsoluteNumberScale: -1)) {
            XCTAssertEqual(($0 as? TranslationRuntimeLimits.ValidationError)?.parameter, "maximumNumberPrecision")
            XCTAssertEqual(String(describing: $0), "maximumNumberPrecision must be positive, but was 0")
        }
        XCTAssertThrowsError(try TranslationRuntimeLimits(maximumCompactExponent: -1)) {
            XCTAssertEqual(String(describing: $0), "maximumCompactExponent must be non-negative, but was -1")
        }
        XCTAssertThrowsError(try TranslationRuntimeLimits(maximumCompactExponent: 4_097)) {
            XCTAssertEqual(String(describing: $0), "maximumCompactExponent 4097 exceeds the hard ceiling of 4096")
        }
    }

    func testPrimitivesHaveCheckedSendableConformance() {
        // These generic constraints are checked by Swift 6 at compile time.
        func requireSendable<Value: Sendable>(_ type: Value.Type) {}
        requireSendable(ExactString.self)
        requireSendable(TranslationRuntimeLimits.self)
        requireSendable(TranslationRuntimeLimits.ValidationError.self)
        requireSendable(LanguageFormAxis.self)
        requireSendable(Cardinality.self)
        requireSendable(Ordinality.self)
        requireSendable(Gender.self)
        requireSendable(GrammaticalCase.self)
        requireSendable(Definiteness.self)
        requireSendable(Classifier.self)
        requireSendable(Formality.self)
        requireSendable(Clusivity.self)
        requireSendable(Animacy.self)
        requireSendable(Phonetic.self)
        requireSendable(BidiIsolation.self)
        requireSendable(LocaleMatchType.self)
    }

    private func assertForms<Form: LanguageForm & CaseIterable>(
        _ type: Form.Type, axis: LanguageFormAxis, names: [String],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let forms = Array(type.allCases)
        XCTAssertEqual(type.axis, axis, file: file, line: line)
        XCTAssertEqual(forms.map(\.displayName), names, file: file, line: line)
        XCTAssertEqual(forms.map(\.rawValue), names.map { "\(axis.rawValue)_\($0)" }, file: file, line: line)
        for (form, name) in zip(forms, names) {
            XCTAssertEqual(form.axis, axis, file: file, line: line)
            XCTAssertEqual(form.description, name, file: file, line: line)
            XCTAssertEqual(Form(rawValue: form.rawValue), form, file: file, line: line)
        }
    }

    private func limitValues(_ limits: TranslationRuntimeLimits) -> [Int] {
        [limits.maximumNumberPrecision, limits.maximumAbsoluteNumberScale,
         limits.maximumVisibleDecimalPlaces, limits.maximumCompactExponent,
         limits.maximumExpressionCharacters, limits.maximumExpressionTokens,
         limits.maximumExpressionNestingDepth, limits.maximumGeneratedPlaceholderDepth,
         limits.maximumInterpolatedOutputCharacters, limits.maximumGeneratedExpansionCharacters]
    }
}
