import Foundation
import Darwin
import XCTest
import Lokalized

final class ConcurrencyTests: XCTestCase {
    func testSharedRuntimeKeepsLocaleUnicodeAndBidiSnapshotsIndependent() throws {
        let tags = try ["en", "fr", "ar", "ja"].map(LocaleTag.init)
        let body = #"{"greeting":"LOCALE/{{name}}/{{number}}","é":"composed/{{name}}","e\u0301":"decomposed/{{name}}","plural":{"translation":"{{quantity}}","placeholders":{"quantity":{"value":"count","translations":{"CARDINALITY_ZERO":"zero","CARDINALITY_ONE":"one","CARDINALITY_TWO":"two","CARDINALITY_FEW":"few","CARDINALITY_MANY":"many","CARDINALITY_OTHER":"other"}}}}}"#
        let catalogs = try Dictionary(uniqueKeysWithValues: tags.map { tag in
            (tag, LocalizedCatalog(strings: try LocalizedStringLoader.parse(
                body.replacingOccurrences(of: "LOCALE", with: tag.tag), locale: tag.tag).strings))
        })
        let strings = try makeRuntime(catalogs)
        let failures = concurrently(iterations: 512) { index in
            let tag = tags[index % tags.count]
            let match = try strings.matchFor(tag)
            let isolate = index % 3 == 0
            let options = try TranslationOptions(localeMatchResult: match, bidiIsolation: isolate ? .always : .disabled)
            let name = "caller-\(index)"
            let values: PlaceholderValues = ["name": .text(name), "number": PlaceholderValue(Double.pi)]
            let wrap: @Sendable (String) -> String = { isolate ? "\u{2068}\($0)\u{2069}" : $0 }
            let greeting = try strings.getResult("greeting", placeholders: values, options: options)
            try requireUnits(greeting.translation, "\(tag.tag)/\(wrap(name))/\(wrap("3.141592653589793"))")
            try require(greeting.lookupLocale == tag && greeting.resolvedLocale == tag, "Locale snapshot changed")
            try require(greeting.localeMatchResult === match && greeting.attemptedLocales == [tag], "Match snapshot changed")
            try requireUnits(strings.get("é", placeholders: values, options: options), "composed/\(wrap(name))")
            try requireUnits(strings.get("e\u{0301}", placeholders: values, options: options), "decomposed/\(wrap(name))")
            let plural = try strings.get("plural", placeholders: ["count": .integer(2)], options: options)
            try requireUnits(plural, tag.tag == "ar" ? "two" : "other")
            let keys = try strings.getKeysForLocale(tag)
            try require(keys.contains("é") && keys.contains("e\u{0301}") && keys.count == 4, "Exact key inventory changed")
        }
        XCTAssertEqual(failures, [])
        XCTAssertEqual(try strings.get("greeting", placeholders: ["name": .text("default"), "number": .integer(7)]), "en/default/7")
    }

    func testIndependentResolversDoNotShareGeneratedPlaceholderCaches() throws {
        let en = try LocaleTag("en")
        let body = #"{"k":{"translation":"{{sound}}/{{sound}}/{{term}}","placeholders":{"sound":{"value":"term","translations":{"PHONETIC_VOWEL":"vowel","PHONETIC_CONSONANT":"consonant"}}}}}"#
        let catalogs = [en: LocalizedCatalog(strings: try LocalizedStringLoader.parse(body, locale: "en").strings)]
        let firstCalls = ConcurrencyLog<String>()
        let secondCalls = ConcurrencyLog<String>()
        let first = try makeRuntime(catalogs, resolver: { term, locale in
            try require(locale == en, "First resolver received another locale")
            firstCalls.append(term)
            return .vowel
        })
        let second = try makeRuntime(catalogs, resolver: { term, locale in
            try require(locale == en, "Second resolver received another locale")
            secondCalls.append(term)
            return .consonant
        })
        let failures = concurrently(iterations: 256) { index in
            let term = "term-\(index)"
            let values: PlaceholderValues = ["term": .text(term)]
            try requireUnits(first.get("k", placeholders: values), "vowel/vowel/\(term)")
            try requireUnits(second.get("k", placeholders: values), "consonant/consonant/\(term)")
        }
        XCTAssertEqual(failures, [])
        let expected = Set((0..<256).map { "term-\($0)" })
        XCTAssertEqual(Set(firstCalls.values), expected)
        XCTAssertEqual(Set(secondCalls.values), expected)
        XCTAssertEqual(firstCalls.values.count, 256)
        XCTAssertEqual(secondCalls.values.count, 256)
    }

    func testConcurrentObserverReentryAndThrowingHandlersRetainEachCall() throws {
        let en = try LocaleTag("en")
        let fr = try LocaleTag("fr")
        let roots = try (0..<128).map { index in
            try LocalizedString(key: ExactString("item-\(index)"), translation: "outer/\(index)/{{token}}")
        } + [LocalizedString(key: "inner", translation: "nested/{{token}}")]
        let catalogs = [en: LocalizedCatalog(strings: roots), fr: LocalizedCatalog(strings: [])]
        let events = ConcurrencyLog<TranslationFallbackEvent>()
        let nested = ConcurrencyLog<String>()
        let holder = ConcurrencyRuntimeHolder()
        let strings = try makeRuntime(catalogs, observer: TranslationFallbackObserver { event in
            // Release the holder's lock before reentering the same runtime.
            let current = try holder.get()
            let result = try current.get("inner", placeholders: ["token": .text(event.key.description)],
                                         options: .forLocale(en))
            nested.append(result)
            events.append(event)
        })
        holder.install(strings)
        defer { holder.clear() }
        let failures = concurrently(iterations: 128) { index in
            let key = ExactString("item-\(index)")
            let token = "token-\(index)"
            let match = try strings.matchFor(fr)
            let result = try strings.getResult(key, placeholders: ["token": .text(token)], options: .forLocaleMatch(match))
            try requireUnits(result.translation, "outer/\(index)/\(token)")
            try require(result.localeMatchResult === match && result.attemptedLocales == [fr, en], "Reentry changed outer attempts")
            let marker = ConcurrencyMarkerError(index: index)
            let throwing = try TranslationOptions(locale: fr, translationFailureHandler: TranslationFailureHandler { failure in
                try require(failure.key == ExactString("missing-\(index)"), "Handler received another call's key")
                guard case .text(let actual)? = failure.placeholders["token"] else {
                    throw ConcurrencyCheckError(message: "Handler lost caller value")
                }
                try requireUnits(actual, token)
                throw marker
            })
            do {
                _ = try strings.get(ExactString("missing-\(index)"), placeholders: ["token": .text(token)], options: throwing)
                throw ConcurrencyCheckError(message: "Throwing handler returned a value")
            } catch {
                try require((error as? ConcurrencyMarkerError) === marker, "Handler error identity changed")
            }
        }
        XCTAssertEqual(failures, [])
        XCTAssertEqual(events.values.count, 128)
        XCTAssertEqual(Set(events.values.map(\.key)), Set((0..<128).map { ExactString("item-\($0)") }))
        XCTAssertTrue(events.values.allSatisfy { $0.lookupLocale == fr && $0.resolvedLocale == en &&
            $0.attemptedLocales == [fr, en] && $0.precedingFailures.count == 1 &&
            $0.precedingFailures[0].reason == .missingTranslation })
        XCTAssertEqual(Set(nested.values), Set((0..<128).map { "nested/item-\($0)" }))
    }

    func testConcurrentDirectoryAndCallerStreamLoadsKeepBudgetsAndWarningsLocal() throws {
        let pointer = try XCTUnwrap(FileManager.default.temporaryDirectory.path.withCString { realpath($0, nil) })
        let root = URL(fileURLWithPath: String(cString: pointer), isDirectory: true).appendingPathComponent(UUID().uuidString)
        free(pointer)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let body = #"{"k":{"translation":"{{n}}","placeholders":{"n":{"value":"count","translations":{"CARDINALITY_ONE":"one"}}}}}"#
        let bytes = Data(body.utf8)
        try bytes.write(to: root.appendingPathComponent("en"))
        try bytes.write(to: root.appendingPathComponent("fr.JSON"))
        let expectedLocales: Set<LocaleTag> = [try LocaleTag("en"), try LocaleTag("fr")]
        let exact = try LocalizedStringLoadingOptions(maximumInputBytes: bytes.count,
            maximumTotalInputBytes: bytes.count * 2, maximumLocalizedStringsFiles: 2, maximumWarnings: 2)
        let short = try LocalizedStringLoadingOptions(maximumInputBytes: bytes.count,
            maximumTotalInputBytes: bytes.count * 2 - 1, maximumLocalizedStringsFiles: 2, maximumWarnings: 2)
        let failures = concurrently(iterations: 96) { index in
            let warnings = ConcurrencyLog<LocalizedStringWarning>()
            let files = try LocalizedStringLoader.loadFromDirectory(root, warningHandler: { warning in
                // Reenter parsing from the warning callback, with its own session.
                try require(LocalizedStringLoader.parse("{}", locale: "en").strings.isEmpty, "Warning reentry changed parsing")
                warnings.append(warning)
            }, loadingOptions: exact)
            try require(Set(files.keys) == expectedLocales, "Concurrent directory load lost a locale")
            try require(warnings.values.count == 2 && files.values.allSatisfy { $0.warnings.count == 1 }, "Warnings escaped their load")
            try require(Set(warnings.values.map(\.source)) == [root.appendingPathComponent("en").path, root.appendingPathComponent("fr.JSON").path],
                        "Warning source escaped its file")
            do {
                _ = try LocalizedStringLoader.loadFromDirectory(root, loadingOptions: short)
                throw ConcurrencyCheckError(message: "Aggregate byte limit was not enforced")
            } catch let error as StringsParseError {
                try require(error.source == root.appendingPathComponent("fr.JSON").path &&
                    error.message.contains("aggregate maximum of \(bytes.count * 2 - 1) input bytes"), "Aggregate diagnostic escaped its load")
            }
            let input = InputStream(data: bytes)
            input.open()
            defer { input.close() }
            let parsed = try LocalizedStringLoader.parse(input, locale: "en", source: "stream-\(index)")
            try require(parsed.sources == ["stream-\(index)"] && parsed.strings.count == 1 && parsed.warnings.count == 1,
                        "Caller stream state escaped its parse")
            try require(input.streamStatus != .closed, "Loader closed the caller's stream")
        }
        XCTAssertEqual(failures, [])
    }
}

private func makeRuntime(_ catalogs: [LocaleTag: LocalizedCatalog], resolver: PhoneticResolver? = nil,
                         observer: TranslationFallbackObserver? = nil) throws -> DefaultStrings {
    let en = try LocaleTag("en")
    return try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { catalogs },
        localeSupplier: { _ in en }, fallbackLocale: en, translationFallbackObserver: observer,
        phoneticResolver: resolver, bidiIsolation: .disabled))
}

private func concurrently(iterations: Int, _ body: @escaping @Sendable (Int) throws -> Void) -> [String] {
    let failures = ConcurrencyLog<String>()
    DispatchQueue.concurrentPerform(iterations: iterations) { index in
        do { try body(index) }
        catch { failures.append("\(index): \(error)") }
    }
    return failures.values.sorted()
}

private func require(_ value: Bool, _ message: String) throws {
    if !value { throw ConcurrencyCheckError(message: message) }
}
private func requireUnits(_ actual: String, _ expected: String) throws {
    try require(actual.utf16.elementsEqual(expected.utf16), "Expected \(expected), received \(actual)")
}
private struct ConcurrencyCheckError: Error { let message: String }
private final class ConcurrencyMarkerError: Error, Sendable {
    let index: Int
    init(index: Int) { self.index = index }
}
private final class ConcurrencyLog<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Value] = []
    var values: [Value] { lock.lock(); defer { lock.unlock() }; return recorded }
    func append(_ value: Value) { lock.lock(); defer { lock.unlock() }; recorded.append(value) }
}
private final class ConcurrencyRuntimeHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var strings: DefaultStrings?
    func install(_ value: DefaultStrings) { lock.lock(); defer { lock.unlock() }; strings = value }
    func clear() { lock.lock(); defer { lock.unlock() }; strings = nil }
    func get() throws -> DefaultStrings {
        lock.lock(); defer { lock.unlock() }
        guard let strings else { throw ConcurrencyCheckError(message: "Reentry runtime was not installed") }
        return strings
    }
}
