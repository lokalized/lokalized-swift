import XCTest
@testable import Lokalized

final class BidiRendererTests: XCTestCase {
    func testBalancesIsolatesAndPreservesOneCompleteRun() throws {
        XCTAssertEqual(try BidiRenderer.isolate(""), "")
        for opening in ["\u{2066}", "\u{2067}", "\u{2068}"] {
            let complete = opening + "a\u{2069}"
            XCTAssertEqual(try BidiRenderer.isolate(complete), complete)
        }
        XCTAssertEqual(try BidiRenderer.isolate("\u{2069}a\u{2069}"), "\u{2068}a\u{2069}")
        XCTAssertEqual(try BidiRenderer.isolate("\u{2066}a"), "\u{2068}\u{2066}a\u{2069}\u{2069}")
        XCTAssertEqual(try BidiRenderer.isolate("\u{2068}a\u{2069}b"), "\u{2068}\u{2068}a\u{2069}b\u{2069}")
    }

    func testRejectsOversizedTextBeforeBalancingOrBalancedFastPath() throws {
        for text in ["\u{2068}ab\u{2069}", String(repeating: "\u{2069}", count: 20)] {
            XCTAssertThrowsError(try BidiRenderer.isolate(text, maximumCharacters: 3)) { error in
                XCTAssertEqual((error as? TranslationEvaluationError)?.message,
                               "Interpolated output exceeds the maximum of 3 characters")
            }
        }
        XCTAssertEqual(try BidiRenderer.isolate("😀", maximumCharacters: 4), "\u{2068}😀\u{2069}")
        XCTAssertThrowsError(try BidiRenderer.isolate("😀", maximumCharacters: 3))
        XCTAssertThrowsError(try BidiRenderer.isolate("", maximumCharacters: -2))
    }

    func testExplicitScriptOverridesLikelyDirection() throws {
        for (tag, expected) in [("ar", true), ("ar-Latn", false), ("ar-Zzzz", false),
                                ("he", true), ("en", false), ("und-Hebr", true), ("und-Zzzz-IL", false)] {
            let renderer = BidiRenderer(locale: try LocaleTag(tag), isolation: .rtlLocales, limits: .defaults)
            XCTAssertEqual(try renderer.render(name: "x", value: .text("v"), remaining: 10),
                           expected ? "\u{2068}v\u{2069}" : "v", tag)
        }
    }

    func testIsolatedCustomValuesAreCachedByExactNameOnly() throws {
        let display = BidiTestDisplay()
        let isolated = BidiRenderer(locale: try LocaleTag("en"), isolation: .always, limits: .defaults)
        XCTAssertEqual(try isolated.render(name: "é", value: .custom(display), remaining: 10), "\u{2068}v1\u{2069}")
        XCTAssertEqual(try isolated.render(name: "é", value: .custom(display), remaining: 9), "\u{2068}v1\u{2069}")
        XCTAssertEqual(try isolated.render(name: "e\u{0301}", value: .custom(display), remaining: 8), "\u{2068}v2\u{2069}")
        XCTAssertEqual(display.limits, [10, 8])
        let plain = BidiRenderer(locale: try LocaleTag("en"), isolation: .disabled, limits: .defaults)
        XCTAssertEqual(try plain.render(name: "x", value: .custom(display), remaining: 7), "v3")
        XCTAssertEqual(try plain.render(name: "x", value: .custom(display), remaining: 6), "v4")
        XCTAssertEqual(display.limits, [10, 8, 7, 6])
        XCTAssertNil(try isolated.render(name: "null", value: .null, remaining: 5))
    }

    func testRepeatedPlaceholderRefusalReportsWholeBudget() throws {
        let limits = try TranslationRuntimeLimits(maximumInterpolatedOutputCharacters: 11)
        let parsed = try LocalizedStringLoader.parse(#"{"k":"{{x}}/{{x}}"}"#, locale: "en")
        let engine = try CompiledCatalogResolution(parsed, locale: LocaleTag("en"), runtimeLimits: limits)
        let renderer = BidiRenderer(locale: try LocaleTag("en"), isolation: .always, limits: limits)
        XCTAssertThrowsError(try engine.resolve("k", placeholders: ["x": .text("abcd")], callerValueRenderer: renderer.render)) { error in
            XCTAssertEqual((error as? TranslationEvaluationError)?.message,
                           "Interpolated output exceeds the maximum of 11 characters")
        }
    }

    func testOnlyCallerValuesAreIsolatedInsideGeneratedFragments() throws {
        let parsed = try LocalizedStringLoader.parse(#"{"k":{"translation":"{{fragment}}","placeholders":{"fragment":{"translation":"owned {{caller}}"}}}}"#, locale: "ar")
        let engine = try CompiledCatalogResolution(parsed, locale: LocaleTag("ar"))
        let renderer = BidiRenderer(locale: try LocaleTag("ar"), isolation: .rtlLocales, limits: .defaults)
        guard case .translation(let text, _) = try engine.resolve("k", placeholders: ["caller": .text("Sarah")], callerValueRenderer: renderer.render) else {
            return XCTFail("Expected a translation")
        }
        XCTAssertEqual(text, "owned \u{2068}Sarah\u{2069}")
    }

    func testFailureKeyIsLenientAndReturnsOriginalOnEveryRenderingError() throws {
        let locale = try LocaleTag("ar")
        XCTAssertEqual(BidiRenderer.failureKey("}} {{x}} {{missing}} {{bad name}} {{", values: ["x": .text("v")],
            locale: locale, isolation: .rtlLocales, limits: .defaults),
            "}} \u{2068}v\u{2069} {{missing}} {{bad name}} {{")
        let display = BidiTestDisplay()
        let small = try TranslationRuntimeLimits(maximumInterpolatedOutputCharacters: 2)
        XCTAssertEqual(BidiRenderer.failureKey("abc{{x}}", values: ["x": .custom(display)],
            locale: locale, isolation: .always, limits: small), "abc{{x}}")
        XCTAssertTrue(display.limits.isEmpty)
        let error = BidiTestError()
        XCTAssertEqual(BidiRenderer.failureKey("{{x}}", values: ["x": .custom(BidiThrowingDisplay(error: error))],
            locale: locale, isolation: .always, limits: .defaults), "{{x}}")
    }
}

private final class BidiTestDisplay: PlaceholderConvertible, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Int?] = []
    var limits: [Int?] { lock.lock(); defer { lock.unlock() }; return recorded }
    func lokalizedDescription(maximumCharacters: Int?) throws -> String {
        lock.lock(); defer { lock.unlock() }
        recorded.append(maximumCharacters)
        return "v\(recorded.count)"
    }
}
private final class BidiTestError: Error, Sendable {}
private struct BidiThrowingDisplay: PlaceholderConvertible {
    let error: BidiTestError
    func lokalizedDescription(maximumCharacters: Int?) throws -> String { throw error }
}
