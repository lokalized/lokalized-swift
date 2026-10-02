import Foundation
import XCTest
import Lokalized

final class TranslationContractTests: XCTestCase {
    private let english = try! LocaleTag("en")
    private let french = try! LocaleTag("fr")

    private func translated(lookup: LocaleTag? = nil, match: LocaleMatchResult? = nil,
                            resolved: LocaleTag? = nil, attempts: [LocaleTag]? = nil) throws -> TranslationResult {
        try TranslationResult(key: "hello", translation: "Bonjour", lookupLocale: lookup ?? english,
                              localeMatchResult: match, resolvedLocale: resolved ?? french,
                              attemptedLocales: attempts ?? [english, french], status: .translated)
    }
    private func match(_ type: LocaleMatchType) throws -> LocaleMatchResult {
        let range = try LanguageRange("en")
        return try LocaleMatchResult(requestedLanguageRanges: [range], locale: type == .noMatch ? nil : english,
                                     languageRange: type == .noMatch ? nil : range,
                                     effectiveWeight: type == .noMatch ? nil : 1, matchType: type,
                                     fallbackLocale: english, consideredLocales: [english, french])
    }
    private func argument(_ message: String, _ operation: () throws -> Void,
                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual((error as? TranslationEvaluationError)?.kind, .invalidArgument, file: file, line: line)
            XCTAssertEqual((error as? TranslationEvaluationError)?.message, message, file: file, line: line)
        }
    }

    func testExactPlaceholderCollectionPreservesCanonicalDistinctionsAndNull() {
        let values: PlaceholderValues = ["é": .text("NFC"), "e\u{301}": .text("NFD"), "nil": .null]
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values.keys, [ExactString("é"), ExactString("e\u{301}"), "nil"])
        guard case .text("NFC") = values["é"], case .text("NFD") = values["e\u{301}"], case .null = values["nil"] else {
            return XCTFail("Exact values or explicit null were lost")
        }
        XCTAssertNil(values["absent"])
        XCTAssertEqual(values.map(\.key), values.keys.sorted())
        let replaced = PlaceholderValues(entries: [("x", .integer(1)), ("x", .integer(2))])
        guard case .integer(2) = replaced["x"] else { return XCTFail("Last exact value should replace") }
    }

    func testCatalogRetainsDuplicateRootOrderAndDeferredEntryLabels() throws {
        let first = try LocalizedString(key: "a", translation: "one")
        let second = try LocalizedString(key: "a", translation: "two")
        let ordered = LocalizedCatalog(strings: [first, second])
        XCTAssertEqual(ordered.count, 2)
        XCTAssertEqual(ordered.strings.map(\.translation), ["one", "two"])
        XCTAssertNil(ordered.suppliedKeys)
        let literal: LocalizedCatalog = ["other": first, "a": second]
        XCTAssertEqual(literal.suppliedKeys, ["other", "a"])
        XCTAssertEqual(literal.orderedStrings, [first, second])
        let exact: LocalizedCatalog = ["é": try LocalizedString(key: "é", translation: "one"),
                                       "e\u{301}": try LocalizedString(key: "e\u{301}", translation: "two")]
        XCTAssertEqual(exact.count, 2)
    }

    func testConfigurationDefersSupplierValidationAndDoesNotInvokeCallbacks() {
        let counter = ContractCounter()
        let config = StringsConfiguration(localizedStringSupplier: { counter.increment(); return [:] },
            localeSupplier: { _ in counter.increment(); return selfTag },
            localeMatchSupplier: { _ in counter.increment(); throw ContractIdentityError() }, fallbackLocale: english)
        XCTAssertNotNil(config.localeSupplier)
        XCTAssertNotNil(config.localeMatchSupplier)
        XCTAssertEqual(counter.count, 0)
        let missing = StringsConfiguration(fallbackLocale: english)
        XCTAssertNil(missing.localizedStringSupplier)
        XCTAssertNil(missing.runtimeLimits)
        XCTAssertNil(missing.bidiIsolation)
        XCTAssertNil(missing.languageRangeEquivalents)
    }

    func testOptionsDistinguishOmissionDisabledAndEmptyRanges() throws {
        XCTAssertEqual(TranslationOptions(), .none)
        XCTAssertNil(TranslationOptions.none.bidiIsolation)
        let disabled = try TranslationOptions(bidiIsolation: .disabled)
        XCTAssertEqual(disabled.bidiIsolation, .disabled)
        XCTAssertNotEqual(disabled, .none)
        let emptyRanges = try TranslationOptions.forLanguageRanges([])
        XCTAssertEqual(emptyRanges.languageRanges, [])
        XCTAssertNotEqual(emptyRanges, .none)
        XCTAssertEqual(try TranslationOptions.forLocale("EN-us").locale?.tag, "en-US")
        let supplied = try match(.exact)
        XCTAssertTrue(TranslationOptions.forLocaleMatch(supplied).localeMatchResult === supplied)
    }

    func testOptionsRefuseMultipleSourcesOversizeAndMalformedTypedLocale() throws {
        argument("Specify either locale, languageRanges, or localeMatchResult, not more than one") {
            _ = try TranslationOptions(locale: english, languageRanges: [])
        }
        argument("Specify either locale, languageRanges, or localeMatchResult, not more than one") {
            _ = try TranslationOptions(languageRanges: [], localeMatchResult: match(.exact))
        }
        argument("At most 32 language ranges are supported, but received 33") {
            _ = try TranslationOptions.forLanguageRanges(Array(repeating: LanguageRange("en"), count: 33))
        }
        XCTAssertThrowsError(try TranslationOptions.forLocale(LocaleTag.forLanguageTag("en-x-lvariant-NY"))) { error in
            XCTAssertEqual((error as? TranslationEvaluationError)?.kind, .invalidArgument)
            XCTAssertTrue((error as? TranslationEvaluationError)?.message.hasPrefix("Locale override") == true)
            XCTAssertTrue((error as? TranslationEvaluationError)?.cause is LocaleTagError)
        }
    }

    func testOptionsEqualityPreservesCallbackIdentity() throws {
        let handler = TranslationFailureHandler.returnKey()
        XCTAssertEqual(try TranslationOptions(translationFailureHandler: handler), try TranslationOptions(translationFailureHandler: handler))
        XCTAssertNotEqual(try TranslationOptions(translationFailureHandler: handler), try TranslationOptions(translationFailureHandler: .returnKey()))
        XCTAssertTrue(TranslationFallbackPolicy.fallbackOnAnyFailure() === TranslationFallbackPolicy.fallbackOnAnyFailure())
        let observer = TranslationFallbackObserver { _ in }
        XCTAssertEqual(Set([try TranslationOptions(translationFallbackObserver: observer), try TranslationOptions(translationFallbackObserver: observer)]).count, 1)
    }

    func testResultsRetainTypedMatchAndCauseIdentityAndExactText() throws {
        let supplied = try match(.exact)
        let success = try translated(match: supplied)
        XCTAssertTrue(success.localeMatchResult === supplied)
        XCTAssertEqual(success.lookupLocale, english)
        XCTAssertEqual(success.resolvedLocale, french)
        let cause = ContractIdentityError()
        let failed = try TranslationResult(key: "é", translation: "e\u{301}", lookupLocale: english,
            localeMatchResult: supplied, resolvedLocale: nil, attemptedLocales: [english], status: .returnedString,
            failureReason: .resolutionFailure, cause: cause)
        XCTAssertTrue((failed.cause as? ContractIdentityError) === cause)
        XCTAssertEqual(Array(failed.key.string.utf16), Array("é".utf16))
        XCTAssertEqual(Array(failed.translation.utf16), Array("e\u{301}".utf16))
    }

    func testResultInvariantsAndValidationPriorityMatchJava() throws {
        argument("A translated result requires a resolved locale and no failure outcome") {
            _ = try TranslationResult(key: "x", translation: "x", lookupLocale: english, resolvedLocale: nil,
                                      attemptedLocales: [], status: .translated)
        }
        argument("A failure-handler result requires a failure reason and no resolved locale") {
            _ = try TranslationResult(key: "x", translation: "x", lookupLocale: english, resolvedLocale: french,
                                      attemptedLocales: [], status: .returnedKey)
        }
        argument("A translated result's resolved locale must be present in attempted locales") {
            _ = try translated(attempts: [english])
        }
        for reason in TranslationFailureReason.allCases {
            let cause: (any Error)? = reason == .resolutionFailure ? nil : ContractIdentityError()
            argument("A failure result must carry a cause if and only if its reason is RESOLUTION_FAILURE") {
                _ = try TranslationResult(key: "x", translation: "x", lookupLocale: english, resolvedLocale: nil,
                                          attemptedLocales: [], status: .returnedKey, failureReason: reason, cause: cause)
            }
        }
        argument("Attempted locales must not contain duplicate language tag 'en'") {
            _ = try TranslationResult(key: "x", translation: "x", lookupLocale: english, resolvedLocale: nil,
                                      attemptedLocales: [english, english], status: .translated)
        }
    }

    func testResultUsesTypedLocaleIdentityForAttemptMembership() throws {
        let root = LocaleTag.forLanguageTag("und"), explicit = LocaleTag.forLanguageTag("UND")
        XCTAssertEqual(root.tag, explicit.tag)
        XCTAssertNotEqual(root, explicit)
        argument("A translated result's resolved locale must be present in attempted locales") {
            _ = try translated(lookup: root, resolved: explicit, attempts: [root])
        }
        argument("Attempted locales must not contain duplicate language tag 'und'") {
            _ = try translated(lookup: root, resolved: explicit, attempts: [root, explicit])
        }
    }

    func testIsFallbackCoversEveryNegotiationTypeAndCanonicalDonor() throws {
        for type in [LocaleMatchType.noMatch, .exact, .canonical, .cldrFallback, .likelySubtag, .extendedRange, .primaryLanguage, .wildcard] {
            let value = try translated(match: match(type), resolved: english, attempts: [english])
            XCTAssertEqual(value.isFallback, [.noMatch, .cldrFallback, .likelySubtag, .primaryLanguage].contains(type), "\(type)")
        }
        XCTAssertTrue(try translated().isFallback)
        let moldovan = try LocaleTag("mo"), romanian = try LocaleTag("ro")
        XCTAssertFalse(try translated(lookup: moldovan, resolved: romanian, attempts: [romanian]).isFallback)
        let failed = try TranslationResult(key: "x", translation: "x", lookupLocale: english, localeMatchResult: match(.noMatch),
                                          resolvedLocale: nil, attemptedLocales: [english], status: .returnedKey, failureReason: .missingTranslation)
        XCTAssertTrue(failed.isFallback)
    }

    func testFailureSnapshotsWithoutResultValidationAndMessageDoesNotRenderValues() throws {
        let cause = ContractIdentityError()
        let malformed = LocaleTag.forLanguageTag("en-x-lvariant-NY")
        let supplied = try match(.exact)
        let failure = TranslationFailure(key: "é", lookupLocale: malformed, localeMatchResult: supplied,
                                         attemptedLocales: [english, english, malformed], placeholders: ["secret": .custom(ContractUnrenderedValue())],
                                         reason: .missingTranslation, cause: cause)
        XCTAssertTrue(failure.localeMatchResult === supplied)
        XCTAssertTrue((failure.cause as? ContractIdentityError) === cause)
        XCTAssertEqual(failure.attemptedLocales, [english, english, malformed])
        XCTAssertEqual(failure.message, "Unable to resolve translation key 'é' for locale 'en-x-lvariant-NY'. Reason: MISSING_TRANSLATION. Attempted locales: [en, en, en-x-lvariant-NY]")
        XCTAssertFalse(failure.message.contains("secret"))
    }

    func testPoliciesAndHandlersAreTypedAndThrownErrorsRemainIdentical() throws {
        let safe = TranslationFallbackPolicy.fallbackOnMissingTranslationOrNoMatchingAlternative()
        for reason in TranslationFailureReason.allCases {
            XCTAssertEqual(try safe.shouldTryNextLocale(reason: reason, attemptedLocale: english, cause: nil), reason != .resolutionFailure)
            XCTAssertTrue(try TranslationFallbackPolicy.fallbackOnAnyFailure().shouldTryNextLocale(reason: reason, attemptedLocale: english, cause: nil))
            XCTAssertFalse(try TranslationFallbackPolicy.neverFallback().shouldTryNextLocale(reason: reason, attemptedLocale: english, cause: nil))
        }
        let failure = TranslationFailure(key: "x", lookupLocale: english, attemptedLocales: [], placeholders: .empty, reason: .missingTranslation)
        XCTAssertEqual(try TranslationFailureHandler.returnKey().handle(failure), .returnKey)
        XCTAssertEqual(try TranslationFailureHandler.throwException().handle(failure), .throwException)
        let original = ContractIdentityError()
        XCTAssertThrowsError(try TranslationFailureHandler.returnKey(observer: { _ in throw original }).handle(failure)) { error in
            XCTAssertTrue((error as? ContractIdentityError) === original)
        }
        XCTAssertThrowsError(try TranslationFallbackPolicy { _, _, _ in throw original }.shouldTryNextLocale(reason: .missingTranslation, attemptedLocale: english, cause: nil)) { error in
            XCTAssertTrue((error as? ContractIdentityError) === original)
        }
        XCTAssertNotEqual(TranslationFailureResponse.returnString("é"), .returnString("e\u{301}"))
        XCTAssertEqual(Set([TranslationFailureResponse.returnString("é"), .returnString("e\u{301}")]).count, 2)
    }

    func testFallbackEventRetainsSuccessfulWalkAndRefusesNegotiationOnlyEvents() throws {
        let cause = ContractIdentityError(), supplied = try match(.exact)
        let preceding = try TranslationFallbackEvent.PrecedingFailure(locale: english, reason: .resolutionFailure, cause: cause)
        let event = try TranslationFallbackEvent(translationResult: translated(match: supplied), precedingFailures: [preceding])
        XCTAssertTrue(event.localeMatchResult === supplied)
        XCTAssertTrue(event.precedingFailures[0] === preceding)
        XCTAssertTrue((event.precedingFailures[0].cause as? ContractIdentityError) === cause)
        XCTAssertEqual(event.resolvedLocale, french)
        argument("A fallback event requires one failure for each preceding locale candidate") {
            _ = try TranslationFallbackEvent(translationResult: translated(match: match(.primaryLanguage), resolved: english, attempts: [english]), precedingFailures: [])
        }
        argument("Preceding failures must follow the attempted locale order") {
            _ = try TranslationFallbackEvent(translationResult: translated(), precedingFailures: [.init(locale: french, reason: .missingTranslation)])
        }
        argument("The final attempted locale must supply the fallback translation") {
            _ = try TranslationFallbackEvent(translationResult: translated(resolved: english), precedingFailures: [preceding])
        }
        let original = ContractIdentityError()
        XCTAssertThrowsError(try TranslationFallbackObserver { _ in throw original }.observe(event)) { error in
            XCTAssertTrue((error as? ContractIdentityError) === original)
        }
    }

    func testPrecedingFailureAndMissingErrorRetainPreciseReasonRequirements() throws {
        for reason in TranslationFailureReason.allCases {
            argument("A preceding failure must carry a cause if and only if its reason is RESOLUTION_FAILURE") {
                _ = try TranslationFallbackEvent.PrecedingFailure(locale: english, reason: reason, cause: reason == .resolutionFailure ? nil : ContractIdentityError())
            }
        }
        argument("MissingTranslationException cannot represent a resolution failure cause") {
            _ = try MissingTranslationError(message: "missing", key: "x", placeholders: .empty,
                                            lookupLocale: LocaleTag.forLanguageTag("en-x-lvariant-NY"), reason: .resolutionFailure)
        }
        let supplied = try match(.exact)
        let failure = TranslationFailure(key: "x", lookupLocale: english, localeMatchResult: supplied,
            attemptedLocales: [english, french], placeholders: ["x": .null], reason: .noMatchingAlternative)
        let error = try MissingTranslationError(failure: failure)
        XCTAssertEqual(error.message, failure.message)
        XCTAssertTrue(error.localeMatchResult === supplied)
        XCTAssertEqual(error.reason, .noMatchingAlternative)
        XCTAssertEqual(error.attemptedLocales, [english, french])
        XCTAssertEqual(error.placeholders.count, 1)
    }
}

private let selfTag = LocaleTag.forLanguageTag("en")
private final class ContractIdentityError: Error {}
private struct ContractUnrenderedValue: PlaceholderConvertible {
    func lokalizedDescription(maximumCharacters: Int?) throws -> String { throw ContractIdentityError() }
}
private final class ContractCounter: @unchecked Sendable {
    private let lock = NSLock(); private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
}
