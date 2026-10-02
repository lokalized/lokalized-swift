import XCTest
@testable import Lokalized
@testable import LokalizedConformanceSupport

final class RuntimeSemanticsTests: XCTestCase {
    private func runtime(_ bodies: [(String, String)], request: String = "fr-CA", fallback: String = "en",
                         handler: TranslationFailureHandler? = nil, observer: TranslationFallbackObserver? = nil,
                         limits: TranslationRuntimeLimits? = nil, bidi: BidiIsolation? = nil) throws -> DefaultStrings {
        var catalogs: [LocaleTag: LocalizedCatalog] = [:]
        for (tag, body) in bodies {
            catalogs[try LocaleTag(tag)] = LocalizedCatalog(strings: try LocalizedStringLoader.parse(body, locale: tag).strings)
        }
        let snapshot = catalogs
        let requested = try LocaleTag(request)
        return try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { snapshot },
            localeSupplier: { _ in requested }, fallbackLocale: LocaleTag(fallback),
            translationFailureHandler: handler, translationFallbackObserver: observer,
            runtimeLimits: limits, bidiIsolation: bidi))
    }

    func testStandaloneNativeRuntimeQualification() throws {
        XCTAssertGreaterThan(try ConformanceRunner.runtimeSelfTest(), 50)
    }

    func testPerCallObserverReplacesInstanceAndNilInherits() throws {
        let instance = RuntimeTestRecorder()
        let perCall = RuntimeTestRecorder()
        let strings = try runtime([("en", #"{"k":"en"}"#)], observer: TranslationFallbackObserver { instance.event($0) })
        let observer = TranslationFallbackObserver { perCall.event($0) }
        let overridden = try TranslationOptions(translationFallbackObserver: observer)
        let inherited = try TranslationOptions(translationFallbackObserver: nil)
        XCTAssertEqual(try strings.get("k", options: overridden), "en")
        XCTAssertEqual(perCall.events.count, 1)
        XCTAssertTrue(instance.events.isEmpty)
        XCTAssertEqual(try strings.get("k", options: inherited), "en")
        XCTAssertEqual(instance.events.count, 1)
        XCTAssertEqual(perCall.events.count, 1)
    }

    func testPerCallBidiDisabledExplicitlyOverridesAlways() throws {
        let strings = try runtime([("en", #"{"k":"{{x}}"}"#)], request: "en", bidi: .always)
        let values: PlaceholderValues = ["x": .text("v")]
        XCTAssertEqual(try strings.get("k", placeholders: values), "\u{2068}v\u{2069}")
        XCTAssertEqual(try strings.get("k", placeholders: values, options: TranslationOptions(bidiIsolation: .disabled)), "v")
        XCTAssertEqual(try strings.get("k", placeholders: values, options: TranslationOptions(bidiIsolation: nil)), "\u{2068}v\u{2069}")
    }

    func testNoMatchingAlternativeOutranksLaterMissingEntries() throws {
        let strings = try runtime([("fr-CA", #"{"k":{"alternatives":[{"take == 1":"yes"}]}}"#), ("en", #"{"other":"none"}"#)],
            handler: TranslationFailureHandler { _ in .returnString("fallback") })
        let result = try strings.getResult("k", placeholders: ["take": .integer(0)])
        XCTAssertEqual(result.translation, "fallback")
        XCTAssertEqual(result.failureReason, .noMatchingAlternative)
        XCTAssertNil(result.cause)
        XCTAssertEqual(result.attemptedLocales.map(\.tag), ["fr-CA", "fr", "en"])
    }

    func testIsolatedDisplayIsOncePerNameAndUnisolatedIsPerOccurrence() throws {
        let display = RuntimeTestDisplay()
        let strings = try runtime([("en", #"{"k":"{{x}}/{{x}}"}"#)], request: "en", bidi: .always)
        XCTAssertEqual(try strings.get("k", placeholders: ["x": .custom(display)]), "\u{2068}v1\u{2069}/\u{2068}v1\u{2069}")
        XCTAssertEqual(display.calls.count, 1)
        XCTAssertEqual(try strings.get("k", placeholders: ["x": .custom(display)], options: TranslationOptions(bidiIsolation: .disabled)), "v2/v3")
        XCTAssertEqual(display.calls.count, 3)
        XCTAssertEqual(try strings.get("k", placeholders: ["x": .custom(display)]), "\u{2068}v4\u{2069}/\u{2068}v4\u{2069}")
        XCTAssertEqual(display.calls.count, 4)
    }

    func testFailureHandlerRunsBeforeLenientKeyDisplayAndBidiRefusalReturnsKey() throws {
        let recorder = RuntimeTestRecorder()
        let display = RuntimeTestDisplay(onCall: { recorder.trace("display") })
        let strings = try runtime([("en", #"{"other":"none"}"#)], request: "en",
            handler: TranslationFailureHandler { _ in recorder.trace("handler"); return .returnKey },
            limits: TranslationRuntimeLimits(maximumInterpolatedOutputCharacters: 8), bidi: .always)
        let result = try strings.getResult("{{x}}/{{x}}", placeholders: ["x": .custom(display)])
        XCTAssertEqual(result.translation, "{{x}}/{{x}}")
        XCTAssertEqual(result.status, .returnedKey)
        XCTAssertEqual(result.failureReason, .missingTranslation)
        XCTAssertNil(result.cause)
        XCTAssertEqual(recorder.traces, ["handler", "display"])
        XCTAssertEqual(display.calls, [8])
    }

    func testIsolatedCustomCacheIsPerTemplateWithMemoizedGeneratedFragments() throws {
        let display = RuntimeTestDisplay()
        let strings = try runtime([("en", #"{"k":{"translation":"{{a}}/{{b}}/{{a}}/{{x}}/{{x}}","placeholders":{"a":{"translation":"A{{x}} {{x}}"},"b":{"translation":"B{{x}}"}}}}"#)], request: "en", bidi: .always)
        let a = "A\u{2068}v1\u{2069} \u{2068}v1\u{2069}"
        let b = "B\u{2068}v2\u{2069}"
        XCTAssertEqual(try strings.get("k", placeholders: ["x": .custom(display)]),
                       "\(a)/\(b)/\(a)/\u{2068}v3\u{2069}/\u{2068}v3\u{2069}")
        XCTAssertEqual(display.calls.count, 3)
    }

    func testObserverDiagnosticsDoNotRetainRenderedTextOrCallerValues() throws {
        let recorder = RuntimeTestRecorder()
        let strings = try runtime([("en", #"{"k":"secret {{x}}"}"#)], observer: TranslationFallbackObserver { recorder.event($0) })
        let result = try strings.getResult("k", placeholders: ["x": .text("caller-secret")])
        XCTAssertEqual(result.translation, "secret caller-secret")
        let event = try XCTUnwrap(recorder.events.first)
        let fieldNames = Set(Mirror(reflecting: event).children.compactMap(\.label))
        XCTAssertFalse(fieldNames.contains("translation"))
        XCTAssertFalse(fieldNames.contains("placeholders"))
        XCTAssertTrue(event.localeMatchResult === result.localeMatchResult)
    }

    func testExplicitDisplayPolicyReceivesSuppliedMatchIdentityAndAllOptions() throws {
        let error = RuntimeTestError()
        let strings = try runtime([("en", #"{"other":"none"}"#)], request: "en",
                                  handler: TranslationFailureHandler { _ in throw error })
        let match = try strings.matchFor(LocaleTag("en"))
        let options = try TranslationOptions(localeMatchResult: match, bidiIsolation: .disabled)
        let recorder = RuntimeTestDisplayFailures()
        let adapter = StringsDisplayAdapter(strings, errorDisplayPolicy: .custom { failure in
            recorder.record(failure)
            return "ui"
        })
        XCTAssertEqual(adapter.get("k", placeholders: ["x": .null], options: options), "ui")
        let failure = try XCTUnwrap(recorder.failures.first)
        XCTAssertTrue((failure.error as? RuntimeTestError) === error)
        XCTAssertEqual(failure.options, options)
        XCTAssertTrue(failure.options.localeMatchResult === match)
        XCTAssertEqual(failure.placeholders.keys, ["x"])
        XCTAssertNotNil(failure.placeholders["x"])
    }
}

private final class RuntimeTestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [TranslationFallbackEvent] = []
    private var recordedTraces: [String] = []
    var events: [TranslationFallbackEvent] { lock.lock(); defer { lock.unlock() }; return recordedEvents }
    var traces: [String] { lock.lock(); defer { lock.unlock() }; return recordedTraces }
    func event(_ event: TranslationFallbackEvent) { lock.lock(); defer { lock.unlock() }; recordedEvents.append(event) }
    func trace(_ value: String) { lock.lock(); defer { lock.unlock() }; recordedTraces.append(value) }
}
private final class RuntimeTestDisplay: PlaceholderConvertible, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Int?] = []
    private let onCall: @Sendable () -> Void
    init(onCall: @escaping @Sendable () -> Void = {}) { self.onCall = onCall }
    var calls: [Int?] { lock.lock(); defer { lock.unlock() }; return recorded }
    func lokalizedDescription(maximumCharacters: Int?) throws -> String {
        lock.lock()
        recorded.append(maximumCharacters)
        let count = recorded.count
        lock.unlock()
        onCall()
        return "v\(count)"
    }
}
private final class RuntimeTestError: Error, Sendable {}
private final class RuntimeTestDisplayFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TranslationDisplayFailure] = []
    var failures: [TranslationDisplayFailure] { lock.lock(); defer { lock.unlock() }; return recorded }
    func record(_ failure: TranslationDisplayFailure) { lock.lock(); defer { lock.unlock() }; recorded.append(failure) }
}
