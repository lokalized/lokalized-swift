import CryptoKit
import Foundation
import Lokalized
import XCTest

final class FallbackObserverProfileTests: XCTestCase {
    func testSharedObserverProfile() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Reference/fallback-observer-v1.json")
        let data = try Data(contentsOf: source)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "4c844d73e8d333dde8432cb9e76fcdeb22b4937b50a632205fe74855b6e57d18")
        let profile = try JSONDecoder().decode(ObserverProfile.self, from: data)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rawFixture = try XCTUnwrap(raw["fixture"] as? [String: Any])
        let variants = try XCTUnwrap(rawFixture["catalogVariants"] as? [String: [String: [String: Any]]])
        XCTAssertEqual(profile.formatVersion, 1)
        XCTAssertEqual(profile.profileID, "fallback-observer-v1")
        XCTAssertEqual(profile.profileVersion, "1.0.0")
        XCTAssertEqual(profile.cases.count, 12)
        for row in profile.cases { try run(row, fixture: profile.fixture, variants: variants) }
    }

    private func run(_ row: ObserverRow, fixture: ObserverFixture,
                     variants: [String: [String: [String: Any]]]) throws {
        let inputCatalogs: [String: [String: Any]]
        if let variant = row.catalogVariant { inputCatalogs = try XCTUnwrap(variants[variant], row.id) }
        else { inputCatalogs = fixture.catalogs.mapValues { $0.mapValues { $0 as Any } } }
        var catalogs: [LocaleTag: LocalizedCatalog] = [:]
        for (tag, entries) in inputCatalogs {
            let bytes = try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
            let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
            catalogs[try LocaleTag(tag)] = LocalizedCatalog(strings: try LocalizedStringLoader.parse(text, locale: tag).strings)
        }
        let snapshot = catalogs
        let request = try LocaleTag(fixture.requestLocale)
        let negotiation = try LocaleTag(fixture.negotiationRequestLocale)
        let ties = try fixture.tiebreakerLocalesByLanguageCode.mapValues { try $0.map(LocaleTag.init) }
        let record = ObserverProfileRecorder()
        let marker = ObserverProfileError()
        let firstCause = ObserverProfileError()
        let secondCause = ObserverProfileError()
        let shouldAdvance = row.policy == "advance"
        let shouldThrow = row.observer == "throw"
        let outerKey = row.key
        let nestedKey = row.nestedKey
        let reentry = ObserverReentryBox()
        let negotiated = row.requestMode == "negotiated"
        let localeSupplier: LocaleSupplier?
        let matchSupplier: LocaleMatchSupplier?
        if negotiated {
            localeSupplier = nil
            matchSupplier = { matcher in try matcher.matchFor(negotiation) }
        } else {
            localeSupplier = { _ in request }
            matchSupplier = nil
        }
        let strings = try DefaultStrings(configuration: StringsConfiguration(
            localizedStringSupplier: { snapshot }, localeSupplier: localeSupplier,
            localeMatchSupplier: matchSupplier,
            fallbackLocale: LocaleTag(fixture.fallbackLocale), tiebreakerLocalesByLanguageCode: ties,
            translationFailureHandler: TranslationFailureHandler { _ in record.handler(); return .returnKey },
            translationFallbackPolicy: TranslationFallbackPolicy { reason, locale, cause in
                record.policy("\(locale.tag):\(reason.rawValue)", cause: cause)
                return shouldAdvance
            },
            translationFallbackObserver: TranslationFallbackObserver { event in
                record.instance(event)
                if shouldThrow { throw marker }
                if let nestedKey, event.key.string == outerKey {
                    record.nested(try reentry.get().getResult(ExactString(nestedKey)))
                }
            }))
        reentry.install(strings)
        defer { reentry.clear() }
        let options: TranslationOptions
        if row.observer == "replace" {
            options = try TranslationOptions(translationFallbackObserver: TranslationFallbackObserver { record.perCall($0) })
        } else if row.observer == "inherit" {
            options = try TranslationOptions(translationFallbackObserver: nil)
        } else { options = .none }
        let values: PlaceholderValues
        switch row.placeholderMode {
        case nil: values = .empty
        case "tier-two": values = ["tier": .integer(2)]
        case "throwing-two": values = ["x": .custom(ObserverThrowingDisplay(error: firstCause)),
                                       "y": .custom(ObserverThrowingDisplay(error: secondCause))]
        default: throw ObserverProfileError()
        }
        var result: TranslationResult?
        var caught: (any Error)?
        do { result = try strings.getResult(ExactString(row.key), placeholders: values, options: options) }
        catch { caught = error }
        if row.expected.outcome == "observer-threw" {
            XCTAssertTrue((caught as? ObserverProfileError) === marker, row.id)
            XCTAssertNil(result, row.id)
        } else {
            XCTAssertNil(caught, row.id)
            let returned = try XCTUnwrap(result, row.id)
            XCTAssertEqual(returned.status.rawValue, row.expected.outcome, row.id)
            XCTAssertEqual(returned.translation, row.expected.translation, row.id)
            XCTAssertEqual(returned.attemptedLocales.map(\.tag), row.expected.attemptedLocales, row.id)
            if let isFallback = row.expected.isFallback { XCTAssertEqual(returned.isFallback, isFallback, row.id) }
            if let event = (record.instanceEvents + record.perCallEvents).first {
                XCTAssertNotNil(returned.localeMatchResult, row.id)
                XCTAssertTrue(event.localeMatchResult === returned.localeMatchResult, row.id)
            }
        }
        XCTAssertEqual(record.policyCalls, row.expected.policyCalls, row.id)
        XCTAssertEqual(record.handlerCalls, row.expected.handlerCalls, row.id)
        XCTAssertEqual(record.instanceEvents.map(ObserverEvent.init), row.expected.instanceEvents, row.id)
        XCTAssertEqual(record.perCallEvents.map(ObserverEvent.init), row.expected.perCallEvents, row.id)
        if let expectedNested = row.expected.nestedResult {
            let nested = try XCTUnwrap(record.nestedResults.only, row.id)
            XCTAssertEqual(nested.key.string, expectedNested.key, row.id)
            XCTAssertEqual(nested.translation, expectedNested.translation, row.id)
            XCTAssertEqual(nested.attemptedLocales.map(\.tag), expectedNested.attemptedLocales, row.id)
            XCTAssertTrue(nested.localeMatchResult === record.instanceEvents[1].localeMatchResult, row.id)
        } else { XCTAssertTrue(record.nestedResults.isEmpty, row.id) }
        for event in record.instanceEvents + record.perCallEvents {
            if row.expected.causeIdentity == "distinct-policy-matched" {
                XCTAssertEqual(event.precedingFailures.count, 2, row.id)
                XCTAssertTrue((event.precedingFailures[0].cause as? ObserverProfileError) === firstCause, row.id)
                XCTAssertTrue((event.precedingFailures[1].cause as? ObserverProfileError) === secondCause, row.id)
                XCTAssertTrue((record.policyCauses[0] as? ObserverProfileError) === firstCause, row.id)
                XCTAssertTrue((record.policyCauses[1] as? ObserverProfileError) === secondCause, row.id)
            } else {
                XCTAssertTrue(event.precedingFailures.allSatisfy { $0.cause == nil }, row.id)
            }
        }
    }
}

private struct ObserverProfile: Decodable {
    let formatVersion: Int
    let profileID: String
    let profileVersion: String
    let fixture: ObserverFixture
    let cases: [ObserverRow]
}
private struct ObserverFixture: Decodable {
    let requestLocale: String
    let negotiationRequestLocale: String
    let fallbackLocale: String
    let tiebreakerLocalesByLanguageCode: [String: [String]]
    let catalogs: [String: [String: String]]
}
private struct ObserverRow: Decodable {
    let id: String
    let key: String
    let policy: String
    let observer: String
    let requestMode: String?
    let catalogVariant: String?
    let placeholderMode: String?
    let nestedKey: String?
    let expected: ObserverExpected
}
private struct ObserverExpected: Decodable {
    let outcome: String
    let translation: String?
    let attemptedLocales: [String]?
    let isFallback: Bool?
    let causeIdentity: String?
    let policyCalls: [String]
    let handlerCalls: Int
    let instanceEvents: [ObserverEvent]
    let perCallEvents: [ObserverEvent]
    let nestedResult: ObserverNestedResult?
}
private struct ObserverNestedResult: Decodable {
    let key: String
    let translation: String
    let attemptedLocales: [String]
}
private struct ObserverEvent: Decodable, Equatable {
    let key: String
    let lookupLocale: String
    let resolvedLocale: String
    let attemptedLocales: [String]
    let precedingFailures: [String]

    init(_ event: TranslationFallbackEvent) {
        key = event.key.string
        lookupLocale = event.lookupLocale.tag
        resolvedLocale = event.resolvedLocale.tag
        attemptedLocales = event.attemptedLocales.map(\.tag)
        precedingFailures = event.precedingFailures.map { "\($0.locale.tag):\($0.reason.rawValue)" }
    }
}
private final class ObserverProfileError: Error, Sendable {}
private struct ObserverThrowingDisplay: PlaceholderConvertible {
    let error: ObserverProfileError
    func lokalizedDescription(maximumCharacters: Int?) throws -> String { throw error }
}
private final class ObserverProfileRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var policies: [String] = []
    private var causes: [(any Error)?] = []
    private var handlers = 0
    private var instances: [TranslationFallbackEvent] = []
    private var perCalls: [TranslationFallbackEvent] = []
    private var nestedValues: [TranslationResult] = []
    var policyCalls: [String] { lock.lock(); defer { lock.unlock() }; return policies }
    var policyCauses: [(any Error)?] { lock.lock(); defer { lock.unlock() }; return causes }
    var handlerCalls: Int { lock.lock(); defer { lock.unlock() }; return handlers }
    var instanceEvents: [TranslationFallbackEvent] { lock.lock(); defer { lock.unlock() }; return instances }
    var perCallEvents: [TranslationFallbackEvent] { lock.lock(); defer { lock.unlock() }; return perCalls }
    var nestedResults: [TranslationResult] { lock.lock(); defer { lock.unlock() }; return nestedValues }
    func policy(_ value: String, cause: (any Error)?) {
        lock.lock(); defer { lock.unlock() }; policies.append(value); causes.append(cause)
    }
    func handler() { lock.lock(); defer { lock.unlock() }; handlers += 1 }
    func instance(_ value: TranslationFallbackEvent) { lock.lock(); defer { lock.unlock() }; instances.append(value) }
    func perCall(_ value: TranslationFallbackEvent) { lock.lock(); defer { lock.unlock() }; perCalls.append(value) }
    func nested(_ value: TranslationResult) { lock.lock(); defer { lock.unlock() }; nestedValues.append(value) }
}
private final class ObserverReentryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var strings: DefaultStrings?
    func install(_ value: DefaultStrings) { lock.lock(); defer { lock.unlock() }; strings = value }
    func clear() { lock.lock(); defer { lock.unlock() }; strings = nil }
    func get() throws -> DefaultStrings {
        lock.lock(); defer { lock.unlock() }
        guard let strings else { throw ObserverProfileError() }
        return strings
    }
}
private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
