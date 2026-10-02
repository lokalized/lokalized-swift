import Foundation
import Lokalized

public extension ConformanceRunner {
    /// Native runtime obligations absent from the shared donor corpus: observer
    /// timing, retained callback errors, reentry, concurrency and UI display.
    static func runtimeSelfTest() throws -> Int {
        var checks = 0
        func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            checks += 1
            guard try value() else { throw ConformanceError("Runtime self-test failed: \(message)") }
        }
        func thrown(_ body: () throws -> Void) throws -> any Error {
            checks += 1
            do { try body() } catch { return error }
            throw ConformanceError("Runtime self-test expected an error")
        }
        let missingThenNoMatch = [("fr", #"{"k":{"alternatives":[{"take == 1":"fr"}]}}"#),
                                  ("en", #"{"k":"en"}"#)]
        let observations = RuntimeRecorder()
        let observer = TranslationFallbackObserver { observations.event($0) }
        let observed = try runtime(missingThenNoMatch, observer: observer)
        let result = try observed.getResult("k", placeholders: ["take": .integer(0)])
        let event = try observations.onlyEvent()
        try expect(result.translation == "en" && result.status == .translated, "later candidate succeeds")
        try expect(event.attemptedLocales.map(\.tag) == ["fr-CA", "fr", "en"], "all preceding attempts in order")
        try expect(event.precedingFailures.map(\.reason) == [.missingTranslation, .noMatchingAlternative], "own candidate reasons")
        try expect(event.precedingFailures.allSatisfy { $0.cause == nil }, "non-resolution failures have no causes")
        try expect(event.localeMatchResult === result.localeMatchResult, "event retains negotiation identity")
        try expect(event.resolvedLocale == result.resolvedLocale && event.lookupLocale == result.lookupLocale, "event/result locale agreement")

        let directRecords = RuntimeRecorder()
        let direct = try runtime([("fr-CA", #"{"k":"first"}"#), ("en", #"{"k":"last"}"#)],
                                 observer: TranslationFallbackObserver { directRecords.event($0) })
        try expect(try direct.get("k") == "first" && directRecords.events.isEmpty, "no event for first candidate")
        let failed = try runtime([("en", #"{"other":"none"}"#)],
                                 observer: TranslationFallbackObserver { directRecords.event($0) })
        try expect(try failed.getResult("absent").status == .returnedKey && directRecords.events.isEmpty, "no event for failed lookup")

        let matcher = try DefaultLocaleMatcher(supportedLocales: ["en", "fr"], fallbackLocale: "en")
        let suppliedMatch = try matcher.matchFor(LocaleTag("fr-CA"))
        let negotiatedRecords = RuntimeRecorder()
        let negotiated = try runtime([("fr", #"{"k":"negotiated"}"#), ("en", #"{"k":"last"}"#)], suppliedMatch: suppliedMatch,
            observer: TranslationFallbackObserver { negotiatedRecords.event($0) })
        let negotiatedResult = try negotiated.getResult("k")
        try expect(negotiatedResult.isFallback && negotiatedResult.attemptedLocales.map(\.tag) == ["fr"], "negotiation fallback differs from key fallback")
        try expect(negotiatedRecords.events.isEmpty && negotiatedResult.localeMatchResult === suppliedMatch, "no event for negotiation-only fallback")

        let first = RuntimeMarkerError("first")
        let second = RuntimeMarkerError("second")
        let resolutionBodies = [("fr-CA", #"{"k":"{{x}}"}"#), ("fr", #"{"k":"{{y}}"}"#), ("en", #"{"k":"success"}"#)]
        let causes = RuntimeRecorder()
        let policy = TranslationFallbackPolicy { reason, locale, cause in causes.policy(reason, locale, cause); return true }
        let afterErrors = try runtime(resolutionBodies, policy: policy,
            observer: TranslationFallbackObserver { causes.event($0) })
        let errorValues: PlaceholderValues = ["x": .custom(RuntimeThrowingDisplay(error: first)),
                                              "y": .custom(RuntimeThrowingDisplay(error: second))]
        let recovered = try afterErrors.getResult("k", placeholders: errorValues)
        let causeEvent = try causes.onlyEvent()
        try expect(recovered.translation == "success", "policy can advance past resolution failures")
        try expect(causeEvent.precedingFailures.count == 2 && causeEvent.precedingFailures.allSatisfy { $0.reason == .resolutionFailure }, "all preceding resolution failures")
        try expect((causeEvent.precedingFailures[0].cause as? RuntimeMarkerError) === first &&
                   (causeEvent.precedingFailures[1].cause as? RuntimeMarkerError) === second, "observer retains each original cause")
        try expect(causes.policies.map(\.locale.tag) == ["fr-CA", "fr"] && causes.policies.map(\.reason) == [.resolutionFailure, .resolutionFailure], "policy own reason/locale")
        try expect((causes.policies[0].cause as? RuntimeMarkerError) === first &&
                   (causes.policies[1].cause as? RuntimeMarkerError) === second, "policy sees current cause")

        let failureRecords = RuntimeRecorder()
        let exhausted = try runtime([("fr-CA", resolutionBodies[0].1), ("fr", resolutionBodies[1].1), ("en", #"{"other":"none"}"#)],
            handler: TranslationFailureHandler { failureRecords.failure($0); return .returnString("fallback") },
            policy: .fallbackOnAnyFailure(), observer: TranslationFallbackObserver { failureRecords.event($0) })
        let exhaustion = try exhausted.getResult("k", placeholders: errorValues)
        let failure = try failureRecords.onlyFailure()
        try expect(exhaustion.failureReason == .resolutionFailure && failure.reason == .resolutionFailure, "resolution outranks all other reasons")
        try expect((exhaustion.cause as? RuntimeMarkerError) === first && (failure.cause as? RuntimeMarkerError) === first, "first retained cause wins")
        try expect(exhaustion.localeMatchResult === failure.localeMatchResult && exhaustion.attemptedLocales == failure.attemptedLocales, "failure/result retained match and attempt snapshot")
        try expect(failureRecords.events.isEmpty && failureRecords.failures.count == 1, "one final handler; no failed-lookup event")
        let throwFirst = try runtime([("fr-CA", resolutionBodies[0].1), ("fr", resolutionBodies[1].1), ("en", #"{"other":"none"}"#)],
                                    handler: .throwException(), policy: .fallbackOnAnyFailure())
        let retained = try thrown { _ = try throwFirst.get("k", placeholders: errorValues) }
        try expect((retained as? RuntimeMarkerError) === first, "throw response rethrows original first cause")

        let observerError = RuntimeMarkerError("observer")
        let observerThrows = RuntimeRecorder()
        let throwingObserver = try runtime(missingThenNoMatch,
            handler: TranslationFailureHandler { observerThrows.failure($0); return .returnKey },
            policy: TranslationFallbackPolicy { reason, locale, cause in observerThrows.policy(reason, locale, cause); return true },
            observer: TranslationFallbackObserver { observerThrows.event($0); throw observerError })
        let observedError = try thrown { _ = try throwingObserver.get("k", placeholders: ["take": .integer(0)]) }
        try expect((observedError as? RuntimeMarkerError) === observerError, "observer exception propagates unchanged")
        try expect(observerThrows.events.count == 1 && observerThrows.policies.count == 2 && observerThrows.failures.isEmpty, "observer error cannot resume fallback or call failure handler")
        let policyError = RuntimeMarkerError("policy")
        let policyRecords = RuntimeRecorder()
        let throwingPolicy = try runtime(missingThenNoMatch,
            handler: TranslationFailureHandler { policyRecords.failure($0); return .returnKey },
            policy: TranslationFallbackPolicy { reason, locale, cause in policyRecords.policy(reason, locale, cause); throw policyError },
            observer: TranslationFallbackObserver { policyRecords.event($0) })
        let policyThrown = try thrown { _ = try throwingPolicy.get("k", placeholders: ["take": .integer(0)]) }
        try expect((policyThrown as? RuntimeMarkerError) === policyError && policyRecords.policies.count == 1 && policyRecords.failures.isEmpty && policyRecords.events.isEmpty,
                   "policy exception is outside resolution and failure channels")
        let finalPolicy = try runtime([("en", #"{"other":"none"}"#)], request: "en",
                                      policy: TranslationFallbackPolicy { _, _, _ in throw policyError })
        try expect(try finalPolicy.get("absent") == "absent", "final candidate does not consult policy")

        let reentry = RuntimeReentryBox()
        let reentrant = try runtime([("en", #"{"k":"outer","inner":"nested"}"#)], observer: TranslationFallbackObserver { event in
            reentry.record(event.key)
            if event.key == "k" { reentry.value(try reentry.strings().get("inner")) }
        })
        reentry.install(reentrant)
        defer { reentry.clear() }
        try expect(try reentrant.get("k") == "outer", "observer reentry outer result")
        try expect(reentry.keys == ["k", "inner"] && reentry.values == ["nested"], "same runtime observer reentry has independent state")
        let concurrentRecords = RuntimeRecorder()
        let concurrent = try runtime([("en", #"{"k":"{{name}}"}"#)], observer: TranslationFallbackObserver { concurrentRecords.event($0) })
        let concurrentFailures = RuntimeConcurrentFailures()
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            do {
                let expected = "value-\(index)"
                let actual = try concurrent.get("k", placeholders: ["name": .text(expected)])
                if actual != expected { concurrentFailures.add("\(index): \(actual)") }
            } catch { concurrentFailures.add(String(describing: error)) }
        }
        try expect(concurrentFailures.values.isEmpty && concurrentRecords.events.count == 40, "concurrent attempts and callbacks retain independent snapshots")

        for tag in ["en-US-x-lvariant-POSIX", "ja-JP-x-lvariant-JP"] {
            var traces: [[String]] = []
            for observing in [false, true] {
                let record = RuntimeRecorder()
                let illFormed = try runtime([("fr", #"{"k":"bonjour"}"#)], request: tag, fallback: "fr",
                    handler: TranslationFailureHandler { record.failure($0); return .throwException },
                    policy: TranslationFallbackPolicy { reason, locale, cause in record.policy(reason, locale, cause); return true },
                    observer: observing ? TranslationFallbackObserver { record.event($0) } : nil)
                let error = try thrown { _ = try illFormed.get("k") }
                let refused = try record.onlyFailure()
                try expect(refused.reason == .resolutionFailure && record.events.isEmpty, "invalid attempted result is a resolution failure, even when observed")
                try expect(String(describing: error).contains(tag.hasPrefix("en") ? "duplicate language tag" : "not a well-formed"), "result refusal diagnostic")
                traces.append(record.policies.map { "\($0.locale.tag):\($0.reason.rawValue)" })
            }
            try expect(traces[0] == traces[1], "enabling observation does not validate or change failed candidate walk")
        }

        let donor = try runtime([("en", #"{"k":"{{name}}"}"#)], request: "ar")
        try expect(try donor.get("k", placeholders: ["name": .text("Sarah")]) == "Sarah", "donor locale controls successful bidi")
        try expect(try donor.get("missing {{name}}", placeholders: ["name": .text("Sarah")]) == "missing \u{2068}Sarah\u{2069}", "requested locale controls returned-key bidi")
        let literalHandler = try runtime([("en", #"{"other":"none"}"#)], request: "ar",
            handler: TranslationFailureHandler { _ in .returnString("literal {{name}}") }, bidi: .always)
        try expect(try literalHandler.get("missing", placeholders: ["name": .text("Sarah")]) == "literal {{name}}", "handler return-string stays verbatim")
        let countingDisplay = RuntimeCountingDisplay()
        let templateCache = try runtime([("en", #"{"k":{"translation":"{{a}}/{{b}}/{{a}}/{{x}}/{{x}}","placeholders":{"a":{"translation":"A{{x}} {{x}}"},"b":{"translation":"B{{x}}"}}}}"#)], request: "en", bidi: .always)
        let a = "A\u{2068}v1\u{2069} \u{2068}v1\u{2069}"
        let b = "B\u{2068}v2\u{2069}"
        try expect(try templateCache.get("k", placeholders: ["x": .custom(countingDisplay)]) ==
                   "\(a)/\(b)/\(a)/\u{2068}v3\u{2069}/\u{2068}v3\u{2069}", "bidi conversion is per template and generated expansion is memoized")
        try expect(countingDisplay.count == 3, "one isolated conversion per caller name per template")

        let handlerError = RuntimeMarkerError("handler")
        let handlerRecords = RuntimeRecorder()
        let handlerThrows = try runtime([("en", #"{"other":"none"}"#)],
            handler: TranslationFailureHandler { handlerRecords.failure($0); throw handlerError })
        let uiRecord = RuntimeDisplayRecorder()
        let adapter = StringsDisplayAdapter(handlerThrows, errorDisplayPolicy: .custom { failure in
            uiRecord.record(failure)
            return "display"
        })
        try expect(adapter.get("{{key}}", placeholders: ["caller": .text("v")]) == "display", "portable display policy chooses text")
        let displayFailure = try uiRecord.onlyFailure()
        try expect((displayFailure.error as? RuntimeMarkerError) === handlerError && displayFailure.key == "{{key}}" && displayFailure.placeholders.keys == ["caller"], "UI receives original handler error and inputs")
        try expect(handlerRecords.failures.count == 1, "display adapter invokes throwing handler exactly once")
        try expect(StringsDisplayAdapter(handlerThrows, errorDisplayPolicy: .returnKey).get("{{key}}") == "{{key}}", "UI return-key is literal")
        try expect(StringsDisplayAdapter(handlerThrows, errorDisplayPolicy: .returnString("ui {{key}}")).get("{{key}}") == "ui {{key}}", "UI return-string is literal")
        let successfulAdapter = StringsDisplayAdapter(direct, errorDisplayPolicy: .custom { _ in "unexpected" })
        try expect(successfulAdapter.get("k") == "first", "UI policy is not called after success")
        return checks
    }
}

private func runtime(_ bodies: [(String, String)], request: String = "fr-CA", fallback: String = "en",
                     suppliedMatch: LocaleMatchResult? = nil, handler: TranslationFailureHandler? = nil,
                     policy: TranslationFallbackPolicy? = nil, observer: TranslationFallbackObserver? = nil,
                     bidi: BidiIsolation? = nil) throws -> DefaultStrings {
    var catalogs: [LocaleTag: LocalizedCatalog] = [:]
    for (tag, body) in bodies {
        let locale = try LocaleTag(tag)
        catalogs[locale] = LocalizedCatalog(strings: try LocalizedStringLoader.parse(body, locale: tag).strings)
    }
    let snapshot = catalogs
    let tiebreakers = Dictionary(grouping: snapshot.keys, by: \.language)
        .filter { $0.value.count > 1 }
        .mapValues { $0.sorted { $0.tag < $1.tag } }
    let locale = LocaleTag.forLanguageTag(request)
    let localeSupplier: LocaleSupplier?
    let matchSupplier: LocaleMatchSupplier?
    if let suppliedMatch {
        localeSupplier = nil
        matchSupplier = { _ in suppliedMatch }
    } else {
        localeSupplier = { _ in locale }
        matchSupplier = nil
    }
    return try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { snapshot },
        localeSupplier: localeSupplier, localeMatchSupplier: matchSupplier, fallbackLocale: LocaleTag(fallback),
        tiebreakerLocalesByLanguageCode: tiebreakers,
        translationFailureHandler: handler, translationFallbackPolicy: policy,
        translationFallbackObserver: observer, bidiIsolation: bidi))
}

private final class RuntimeMarkerError: Error, Sendable {
    let label: String
    init(_ label: String) { self.label = label }
}
private struct RuntimeThrowingDisplay: PlaceholderConvertible {
    let error: RuntimeMarkerError
    func lokalizedDescription(maximumCharacters: Int?) throws -> String { throw error }
}
private final class RuntimeCountingDisplay: PlaceholderConvertible, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func lokalizedDescription(maximumCharacters: Int?) throws -> String {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return "v\(calls)"
    }
}
private final class RuntimeRecorder: @unchecked Sendable {
    struct Policy { let reason: TranslationFailureReason; let locale: LocaleTag; let cause: (any Error)? }
    private let lock = NSLock()
    private var recordedEvents: [TranslationFallbackEvent] = []
    private var recordedFailures: [TranslationFailure] = []
    private var recordedPolicies: [Policy] = []
    var events: [TranslationFallbackEvent] { lock.lock(); defer { lock.unlock() }; return recordedEvents }
    var failures: [TranslationFailure] { lock.lock(); defer { lock.unlock() }; return recordedFailures }
    var policies: [Policy] { lock.lock(); defer { lock.unlock() }; return recordedPolicies }
    func event(_ event: TranslationFallbackEvent) { lock.lock(); defer { lock.unlock() }; recordedEvents.append(event) }
    func failure(_ failure: TranslationFailure) { lock.lock(); defer { lock.unlock() }; recordedFailures.append(failure) }
    func policy(_ reason: TranslationFailureReason, _ locale: LocaleTag, _ cause: (any Error)?) {
        lock.lock(); defer { lock.unlock() }; recordedPolicies.append(.init(reason: reason, locale: locale, cause: cause))
    }
    func onlyEvent() throws -> TranslationFallbackEvent {
        guard events.count == 1, let result = events.first else { throw ConformanceError("Expected one fallback event") }
        return result
    }
    func onlyFailure() throws -> TranslationFailure {
        guard failures.count == 1, let result = failures.first else { throw ConformanceError("Expected one runtime failure") }
        return result
    }
}
private final class RuntimeReentryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var runtime: (any Strings)?
    private var recordedKeys: [ExactString] = []
    private var recordedValues: [String] = []
    var keys: [ExactString] { lock.lock(); defer { lock.unlock() }; return recordedKeys }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return recordedValues }
    func install(_ runtime: any Strings) { lock.lock(); defer { lock.unlock() }; self.runtime = runtime }
    func clear() { lock.lock(); defer { lock.unlock() }; runtime = nil }
    func strings() throws -> any Strings {
        lock.lock(); defer { lock.unlock() }
        guard let runtime else { throw ConformanceError("Runtime was not installed for reentry") }
        return runtime
    }
    func record(_ key: ExactString) { lock.lock(); defer { lock.unlock() }; recordedKeys.append(key) }
    func value(_ value: String) { lock.lock(); defer { lock.unlock() }; recordedValues.append(value) }
}
private final class RuntimeConcurrentFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var values: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    func add(_ value: String) { lock.lock(); defer { lock.unlock() }; recorded.append(value) }
}
private final class RuntimeDisplayRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TranslationDisplayFailure] = []
    func record(_ failure: TranslationDisplayFailure) { lock.lock(); defer { lock.unlock() }; recorded.append(failure) }
    func onlyFailure() throws -> TranslationDisplayFailure {
        lock.lock(); defer { lock.unlock() }
        guard recorded.count == 1, let failure = recorded.first else { throw ConformanceError("Expected one display failure") }
        return failure
    }
}
