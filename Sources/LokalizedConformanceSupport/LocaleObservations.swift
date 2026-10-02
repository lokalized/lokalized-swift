import Foundation
import Lokalized

/// Exercises the standalone native matcher against catalog-derived support and
/// explicit oracle inputs. Expected observations never configure the matcher.
enum LocaleObservations {
    static func execute(_ row: BehavioralCase) throws -> JSONValue {
        guard let fixture = row.fixture else { throw ConformanceError("Locale case has no fixture") }
        let fields = try fixture.checkedObject(at: "matcher.fixture")
        let matcher = try matcher(fields, materialized: row.materializedFiles)
        if row.operation == "acceptLanguage" {
            let input = try row.input.checkedObject(at: "acceptLanguage.input", allowed: ["header"])
            try input.requireKeys(["header"], at: "acceptLanguage.input")
            let header: String?
            switch try input.value("header", at: "acceptLanguage.input") {
            case .null: header = nil
            case .string(let value): header = value
            default: throw ConformanceError("Accept-Language input must be a string or explicit null")
            }
            return .object([.test("acceptLanguage", .object([
                .test("bestMatch", .string(try matcher.bestMatchForAcceptLanguage(header)))
            ]))])
        }
        guard row.operation == "matchFor" else { throw ConformanceError("Unregistered locale operation") }
        let input = try row.input.checkedObject(at: "matchFor.input", allowed: ["locale", "languageRanges"])
        guard input.count == 1 else { throw ConformanceError("Match input must specify exactly one locale source") }
        do {
            let result: LocaleMatchResult
            if let value = input["languageRanges"] {
                result = try matcher.matchFor(languageRanges(value, matcher: matcher))
            } else {
                // The Java oracle calls Locale.forLanguageTag before its public
                // matcher. Keep that lenient JDK projection in this adapter;
                // the Swift String matcher itself has a strict ingress.
                result = try matcher.matchFor(LocaleTag.forLanguageTag(input.string("locale", at: "matchFor.input")).tag)
            }
            return .object([.test("match", try observation(result))])
        } catch let error as LocaleMatcherError {
            return thrown(type: "java.lang.IllegalArgumentException", message: error.message)
        } catch let error as LanguageRangeError {
            let type = error.kind == .indexOutOfBounds ? "java.lang.ArrayIndexOutOfBoundsException" : "java.lang.IllegalArgumentException"
            return thrown(type: type, message: error.message)
        } catch let error as LocaleTagError {
            return thrown(type: "java.lang.IllegalArgumentException", message: error.message)
        }
    }

    private static func matcher(_ fixture: [ExactString: JSONValue], materialized: [ExactString: Data]?) throws -> DefaultLocaleMatcher {
        // M3 qualifies negotiation with real parsed catalog contents. Native
        // transport sessions/discovery arrive in M6; this development inventory
        // follows Java's locale filename predicate for the frozen flat fixtures.
        var names = Set<ExactString>()
        for field in ["files", "rawFiles", "rawFilesBase64"] {
            names.formUnion(try fixture.value(field, at: "matcher.fixture").checkedObject(at: field).keys)
        }
        let options = try CatalogObservations.loadingOptions(fixture["loadingOptions"])
        var loaded: [LocaleTag: String] = [:]
        for name in names.sorted() {
            let filename = name.string
            let tag = filename.hasSuffix(".json") ? String(filename.dropLast(5)) : filename
            guard JDKLocaleTag.isCatalogLanguageTag(tag) else { continue }
            let locale = try LocaleTag(tag)
            _ = try LocalizedStringLoader.parse(CatalogObservations.fileBytes(filename, fixture: fixture, materialized: materialized),
                                                locale: locale.tag, source: filename, loadingOptions: options)
            // The current match fixtures contain one file per JDK Locale. A
            // future duplicate/shard fixture needs the actual merge contract.
            guard loaded.updateValue(locale.tag, forKey: locale) == nil else {
                throw ConformanceError("Duplicate locale in M3 matcher fixture inventory: \(locale.tag)")
            }
        }
        guard !loaded.isEmpty else { throw ConformanceError("Locale fixture has no loadable catalogs") }
        let fallback = LocaleTag.forLanguageTag(try fixture.string("fallbackLocale", at: "matcher.fixture"))
        var tiebreakers: [String: [LocaleTag]] = [:]
        if let value = fixture["tiebreakers"], case .null = value {} else if let value = fixture["tiebreakers"] {
            for (language, values) in try value.checkedObject(at: "matcher.fixture.tiebreakers") {
                guard case .array(let rows) = values else { throw ConformanceError("Tiebreaker list must be an array") }
                tiebreakers[language.string] = try rows.map { value in
                    guard case .string(let text) = value else { throw ConformanceError("Tiebreaker must be a locale tag") }
                    return LocaleTag.forLanguageTag(text)
                }
            }
        }
        return try DefaultLocaleMatcher(supportedLocales: Array(loaded.keys), fallbackLocale: fallback,
                                        tiebreakerLocalesByLanguageCode: tiebreakers)
    }

    private static func languageRanges(_ value: JSONValue, matcher: DefaultLocaleMatcher) throws -> [LanguageRange] {
        if case .string(let header) = value { return try matcher.parseLanguageRanges(header) }
        guard case .array(let values) = value else { throw ConformanceError("Language ranges must be a header or explicit array") }
        return try values.map { value in
            if case .string(let range) = value { return try LanguageRange(range) }
            let fields = try value.checkedObject(at: "matchFor.range", allowed: ["range", "weight"])
            try fields.requireKeys(["range"], at: "matchFor.range")
            var weight = 1.0
            if let value = fields["weight"] {
                guard case .number(let literal) = value, let number = Double(literal) else {
                    throw ConformanceError("Range weight must be a JSON number")
                }
                weight = number
            }
            return try LanguageRange(fields.string("range", at: "matchFor.range"), weight: weight)
        }
    }

    private static func observation(_ result: LocaleMatchResult) throws -> JSONValue {
        .object([
            .test("consideredLocales", .array(result.consideredLocales.map(JSONValue.string))),
            .test("effectiveWeight", try result.effectiveWeight.map(number) ?? .null),
            .test("fallbackLocale", .string(result.fallbackLocale)), .test("isMatch", .bool(result.isMatch)),
            .test("languageRange", result.languageRange.map { .string($0.range) } ?? .null),
            .test("locale", result.locale.map(JSONValue.string) ?? .null),
            .test("matchType", .string(matchType(result.matchType))),
            .test("requestedLanguageRanges", .array(try result.requestedLanguageRanges.map { range in
                .object([.test("range", .string(range.range)), .test("weight", try number(range.weight))])
            }))
        ])
    }

    // The frozen JSON envelope spells integral weights without '.0'. Preserve
    // exact binary width through the pinned decimal converter, then emit compact
    // JSON notation (the data model never rounds through Foundation.Decimal).
    private static func number(_ value: Double) throws -> JSONValue {
        guard value.isFinite else { throw ConformanceError("Nonfinite match weight cannot be observed in JSON") }
        let decimal = try ExactDecimal(JavaFloatingPoint.decimalString(value)).strippingTrailingZeros()
        let exponent = decimal.precision - 1 - decimal.scale
        if exponent >= -6 && exponent < 21 { return .number(decimal.plainString) }
        let digits = String(decoding: decimal.digits, as: UTF8.self)
        let mantissa = String(digits.prefix(1)) + (digits.count > 1 ? "." + digits.dropFirst() : "")
        return .number((decimal.signum < 0 ? "-" : "") + mantissa + "e" + (exponent >= 0 ? "+" : "") + String(exponent))
    }

    private static func thrown(type: String, message: String) -> JSONValue {
        .object([.test("thrown", .object([
            .test("causeType", .null), .test("identicalToRetainedCause", .null),
            .test("message", .string(message)), .test("type", .string(type))
        ]))])
    }

    private static func matchType(_ type: LocaleMatchType) -> String {
        switch type {
        case .noMatch: "NONE"
        case .exact: "EXACT"
        case .canonical: "CANONICAL"
        case .cldrFallback: "CLDR_FALLBACK"
        case .likelySubtag: "LIKELY_SUBTAG"
        case .extendedRange: "EXTENDED_RANGE"
        case .primaryLanguage: "PRIMARY_LANGUAGE"
        case .wildcard: "WILDCARD"
        }
    }
}
