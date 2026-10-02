import CryptoKit
import Foundation
import Lokalized

/// An independent audit of the pinned, expanded CLDR vectors and Java examples.
/// This development target reads Reference files; the library never does.
public struct PluralDataAuditReport: Encodable, Sendable {
    public let status: String
    public let cldrVersion: String
    public let vectorSha256: String
    public let pluralSourceSha256: String
    public let dataFingerprint: String
    public let vectorBytes: Int
    public let pluralSourceBytes: Int
    public let tableFormat: String
    public let compiledBytecodeWords: Int
    public let compiledBytecodeBytes: Int
    public let conditionPrograms: Int
    public let cardinalGroups: Int
    public let ordinalGroups: Int
    public let cardinalRangeGroups: Int
    public let cardinalSamples: Int
    public let ordinalSamples: Int
    public let rangeCells: Int
    public let supportInventories: Int
    public let integerExampleRanges: Int
    public let decimalExampleRanges: Int
    public let checks: Int
    public let failedChecks: Int
    /// First 64 mismatches; failedChecks always counts all mismatches.
    public let failures: [String]
}

public extension ConformanceRunner {
    static func pluralDataAudit(referenceDirectory: URL) throws -> PluralDataAuditReport {
        let vectorSHA = "404e2fb3fbff0ee9564226527c0645c723a16afaf76dff2db7942e5015a54926"
        let sourceSHA = "7ade4692762aac80144f915b62de19f29eb039ec3cf28c3f9f2c34b810cdc0e7"
        var referenceBytes: [String: Int] = [:]
        func frozen(_ name: String, sha: String) throws -> [ExactString: JSONValue] {
            let bytes = try boundedRead(referenceDirectory.appendingPathComponent(name), maximumBytes: 4_194_304)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard digest == sha else { throw ConformanceError("Plural reference digest mismatch: \(name)") }
            referenceBytes[name] = bytes.count
            let fields = try JSONReader.parse(bytes, limits: corpusLimits).checkedObject(
                at: name, allowed: ["formatVersion", "cldrVersion", "cardinalRuleGroups", "ordinalRuleGroups", "cardinalRangeGroups"])
            try fields.requireKeys(["formatVersion", "cldrVersion", "cardinalRuleGroups", "ordinalRuleGroups", "cardinalRangeGroups"], at: name)
            guard fields["formatVersion"].numberLiteral == "1", try fields.string("cldrVersion", at: name) == "48.2" else {
                throw ConformanceError("Plural reference version mismatch: \(name)")
            }
            return fields
        }
        let vectors = try frozen("cldr-conformance-vectors.json", sha: vectorSHA)
        let source = try frozen("cldr-plural-data.json", sha: sourceSHA)
        // Public plural lookup canonicalizes locale aliases before selecting a
        // range group. Derive these expectations from the separately pinned
        // raw export, never from the locale kernel under test.
        let localeBytes = try boundedRead(referenceDirectory.appendingPathComponent("cldr-locale-data.json"), maximumBytes: 4_194_304)
        guard SHA256.hash(data: localeBytes).map({ String(format: "%02x", $0) }).joined()
                == "6241d8889b507a6edc0d6dae7e7812c372b62208ba8649701a819de877eade93" else {
            throw ConformanceError("Plural locale reference digest mismatch")
        }
        let localeFields = try JSONReader.parse(localeBytes, limits: corpusLimits).checkedObject(
            at: "locale data", allowed: ["aliases", "cldrVersion", "formatVersion", "likelySubtags", "parentLocales", "rightToLeftScripts", "validity"])
        let aliasFields = try localeFields.value("aliases", at: "locale data").checkedObject(
            at: "locale aliases", allowed: ["language", "region", "script", "variant"])
        var languageAliases: [String: String] = [:]
        for row in try pluralArray(aliasFields.value("language", at: "locale aliases"), path: "language aliases") {
            let fields = try row.checkedObject(at: "language alias", allowed: ["from", "to"])
            let from = try fields.string("from", at: "language alias"), to = try fields.string("to", at: "language alias")
            guard languageAliases.updateValue(to, forKey: from) == nil else { throw ConformanceError("Duplicate reference language alias") }
        }
        guard BuildMetadata.current.cldrVersion == "48.2", PluralTables.cldrVersion == "48.2",
              BuildMetadata.current.dataFingerprint == PluralTables.dataFingerprint, PluralTables.sourceSha256 == sourceSHA else {
            throw ConformanceError("Compiled plural provenance disagrees with the pinned build")
        }
        var checks = 0, failed = 0, failures: [String] = []
        var cardinalSamples = 0, ordinalSamples = 0, rangeCells = 0, supportInventories = 0
        var integerExamples = 0, decimalExamples = 0
        func expect(_ condition: Bool, _ detail: String) {
            checks += 1
            if !condition {
                failed += 1
                if failures.count < 64 { failures.append(detail) }
            }
        }
        func observe(_ detail: String, _ action: () throws -> Bool) {
            do { expect(try action(), detail) }
            catch { expect(false, "\(detail): \(error)") }
        }
        var cardinalTags = Set<String>(), ordinalTags = Set<String>()
        var ordinalRootExamples: [Ordinality: Lokalized.Range<Int>]?
        for ordinal in [false, true] {
            let key = ordinal ? "ordinalRuleGroups" : "cardinalRuleGroups"
            for (groupIndex, group) in try pluralArray(vectors.value(key, at: "vectors"), path: key).enumerated() {
                let fields = try group.checkedObject(at: key, allowed: ["locales", "rules"])
                try fields.requireKeys(["locales", "rules"], at: key)
                let locales = try pluralStrings(fields.value("locales", at: key), path: key + ".locales")
                guard !locales.isEmpty else { throw ConformanceError("Empty CLDR vector locale group") }
                let rules = try pluralArray(fields.value("rules", at: key), path: key + ".rules")
                var categories: [Int] = []
                for rule in rules {
                    let ruleFields = try rule.checkedObject(at: key + ".rules", allowed: ["count", "condition", "samples"])
                    try ruleFields.requireKeys(["count", "condition", "samples"], at: key + ".rules")
                    let count = try ruleFields.string("count", at: key)
                    let category = try pluralCategory(count)
                    categories.append(category)
                    // Conditions are provenance text, never an expected-value
                    // interpreter. The authored expanded samples are the oracle.
                    _ = try ruleFields.string("condition", at: key)
                    let samples = try pluralStrings(ruleFields.value("samples", at: key), path: key + ".samples")
                    for locale in locales {
                        for sample in samples {
                            if ordinal { ordinalSamples += 1 } else { cardinalSamples += 1 }
                            observe("\(key)[\(groupIndex)] \(locale) \(sample) -> \(count)") {
                                let operands = try pluralSampleOperands(sample)
                                if ordinal { return try Ordinality.forOperands(operands, locale: locale) == Ordinality.allCases[category] }
                                return try Cardinality.forOperands(operands, locale: locale) == Cardinality.allCases[category]
                            }
                        }
                    }
                }
                guard !categories.isEmpty, Set(categories).count == categories.count, categories == categories.sorted() else {
                    throw ConformanceError("Invalid CLDR vector categories")
                }
                for locale in locales {
                    if ordinal {
                        guard ordinalTags.insert(locale).inserted else { throw ConformanceError("Duplicate ordinal vector locale") }
                        observe("ordinal supported forms: \(locale)") {
                            try Ordinality.supportedOrdinalitiesForLocale(locale) == categories.map { Ordinality.allCases[$0] }
                        }
                    } else {
                        guard cardinalTags.insert(locale).inserted else { throw ConformanceError("Duplicate cardinal vector locale") }
                        observe("cardinal supported forms: \(locale)") {
                            try Cardinality.supportedCardinalitiesForLocale(locale) == categories.map { Cardinality.allCases[$0] }
                        }
                    }
                    supportInventories += 1
                }
            }
        }
        expect(Cardinality.getSupportedLocaleTags() == cardinalTags.sorted(), "direct cardinal tag inventory")
        expect(Ordinality.getSupportedLocaleTags() == cardinalTags.union(ordinalTags).sorted(), "direct ordinal tag union inventory")
        supportInventories += 2
        for locale in cardinalTags.subtracting(ordinalTags).sorted() {
            observe("missing ordinal group uses undetermined for known cardinal: \(locale)") {
                try Ordinality.supportedOrdinalitiesForLocale(locale) == [.other]
                    && Ordinality.forNumber(.integer(1), locale: locale) == .other
            }
            supportInventories += 1
        }

        // Every category pair is checked, including pairs absent from CLDR's
        // explicit rows and locales absent from the range table. Missing rows
        // take the end category. Direct script/region tags inherit language rows.
        var rangesByLocale: [String: [Int: Int]] = [:]
        for group in try pluralArray(vectors.value("cardinalRangeGroups", at: "vectors"), path: "ranges") {
            let fields = try group.checkedObject(at: "ranges", allowed: ["locales", "ranges"])
            try fields.requireKeys(["locales", "ranges"], at: "ranges")
            let locales = try pluralStrings(fields.value("locales", at: "ranges"), path: "ranges.locales")
            var rows: [Int: Int] = [:]
            for row in try pluralArray(fields.value("ranges", at: "ranges"), path: "ranges.rows") {
                let values = try row.checkedObject(at: "range", allowed: ["start", "end", "result"])
                try values.requireKeys(["start", "end", "result"], at: "range")
                let start = try pluralCategory(values.string("start", at: "range"))
                let end = try pluralCategory(values.string("end", at: "range"))
                let result = try pluralCategory(values.string("result", at: "range"))
                guard rows.updateValue(result, forKey: start * 6 + end) == nil else { throw ConformanceError("Duplicate CLDR range row") }
            }
            for locale in locales {
                guard cardinalTags.contains(locale), rangesByLocale.updateValue(rows, forKey: locale) == nil else {
                    throw ConformanceError("Invalid/duplicate range locale")
                }
            }
        }
        for locale in cardinalTags.sorted() {
            // The direct plural inventories contain four alias spellings:
            // jw->jv, mo->ro, sh->sr-Latn, tl->fil. Their range lookup follows
            // the canonical spelling; in particular mo inherits Romanian rows.
            let canonical = languageAliases[locale] ?? locale
            let rows = rangesByLocale[canonical] ?? rangesByLocale[String(canonical.split(separator: "-")[0])] ?? [:]
            for start in 0..<6 {
                for end in 0..<6 {
                    let result = rows[start * 6 + end] ?? end
                    rangeCells += 1
                    observe("range \(locale) \(start)..\(end) -> \(result)") {
                        try Cardinality.forRange(Cardinality.allCases[start], Cardinality.allCases[end], locale: locale) == Cardinality.allCases[result]
                    }
                }
            }
        }

        // Java's compact example helpers preserve the exported sequence, scale,
        // and infinite flag. These expectations come from the independently
        // hashed source export, rather than the production generated Swift table.
        for ordinal in [false, true] {
            let key = ordinal ? "ordinalRuleGroups" : "cardinalRuleGroups"
            for group in try pluralArray(source.value(key, at: "source"), path: key) {
                let fields = try group.checkedObject(at: key, allowed: ["locales", "rules"])
                let locales = try pluralStrings(fields.value("locales", at: key), path: key + ".locales")
                var integer: [Int: Lokalized.Range<Int>] = [:]
                var decimal: [Int: Lokalized.Range<ExactDecimal>] = [:]
                for rule in try pluralArray(fields.value("rules", at: key), path: key + ".rules") {
                    let values = try rule.checkedObject(at: key, allowed: ["count", "condition", "integerExample", "decimalExample"])
                    let category = try pluralCategory(values.string("count", at: key))
                    let int = try pluralExample(values.value("integerExample", at: key))
                    let dec = try pluralExample(values.value("decimalExample", at: key))
                    if !int.values.isEmpty {
                        let samples = try int.values.map { value -> Int in
                            guard let result = Int(value) else { throw ConformanceError("Invalid pinned integer example") }
                            return result
                        }
                        integer[category] = .init(values: samples, isInfinite: int.infinite)
                    }
                    if !dec.values.isEmpty {
                        decimal[category] = .init(values: try dec.values.map { try ExactDecimal($0) }, isInfinite: dec.infinite)
                    }
                }
                for locale in locales {
                    integerExamples += integer.count
                    if ordinal {
                        observe("ordinal integer examples \(locale)") {
                            try Ordinality.exampleIntegerValuesForLocale(locale) == Dictionary(uniqueKeysWithValues: integer.map { (Ordinality.allCases[$0.key], $0.value) })
                        }
                    } else {
                        decimalExamples += decimal.count
                        observe("cardinal integer examples \(locale)") {
                            try Cardinality.exampleIntegerValuesForLocale(locale) == Dictionary(uniqueKeysWithValues: integer.map { (Cardinality.allCases[$0.key], $0.value) })
                        }
                        observe("cardinal decimal examples \(locale)") {
                            try Cardinality.exampleDecimalValuesForLocale(locale) == Dictionary(uniqueKeysWithValues: decimal.map { (Cardinality.allCases[$0.key], $0.value) })
                        }
                    }
                }
                if ordinal, locales.contains("und") {
                    ordinalRootExamples = Dictionary(uniqueKeysWithValues: integer.map { (Ordinality.allCases[$0.key], $0.value) })
                }
            }
        }
        guard let ordinalRootExamples else { throw ConformanceError("Missing ordinal root examples in pinned export") }
        for locale in cardinalTags.subtracting(ordinalTags).sorted() {
            integerExamples += ordinalRootExamples.count
            observe("ordinal root integer examples \(locale)") {
                try Ordinality.exampleIntegerValuesForLocale(locale) == ordinalRootExamples
            }
        }
        // These fixed totals catch incomplete reference traversal even when the
        // remaining observations happen to agree.
        guard cardinalSamples == 12_396, ordinalSamples == 2_645, rangeCells == 8_064,
              cardinalTags.count == 224, ordinalTags.count == 108, supportInventories == 450,
              integerExamples == 796, decimalExamples == 440, checks == 24_227 else {
            throw ConformanceError("Incomplete CLDR sample/range inventory traversal")
        }
        return .init(status: failed == 0 ? "passed" : "failed", cldrVersion: "48.2", vectorSha256: vectorSHA,
                     pluralSourceSha256: sourceSHA, dataFingerprint: BuildMetadata.current.dataFingerprint,
                     vectorBytes: referenceBytes["cldr-conformance-vectors.json"]!, pluralSourceBytes: referenceBytes["cldr-plural-data.json"]!,
                     tableFormat: "dnf-u32-v1", compiledBytecodeWords: PluralTables.bytecode.count,
                     compiledBytecodeBytes: PluralTables.bytecode.count * 4,
                     conditionPrograms: Set((PluralTables.cardinalGroups + PluralTables.ordinalGroups).flatMap { $0.rules.map(\.conditionOffset) }).count,
                     cardinalGroups: PluralTables.cardinalGroups.count, ordinalGroups: PluralTables.ordinalGroups.count,
                     cardinalRangeGroups: PluralTables.rangeGroups.count,
                     cardinalSamples: cardinalSamples, ordinalSamples: ordinalSamples, rangeCells: rangeCells,
                     supportInventories: supportInventories, integerExampleRanges: integerExamples, decimalExampleRanges: decimalExamples,
                     checks: checks, failedChecks: failed, failures: failures)
    }
}

private func pluralArray(_ value: JSONValue, path: String) throws -> [JSONValue] {
    guard case .array(let rows) = value else { throw ConformanceError("Expected array at \(path)") }
    return rows
}

private func pluralStrings(_ value: JSONValue, path: String) throws -> [String] {
    try pluralArray(value, path: path).map {
        guard case .string(let value) = $0 else { throw ConformanceError("Expected string at \(path)") }
        return value
    }
}

private func pluralCategory(_ count: String) throws -> Int {
    guard let index = ["zero", "one", "two", "few", "many", "other"].firstIndex(of: count) else {
        throw ConformanceError("Unknown pinned CLDR count \(count)")
    }
    return index
}

private func pluralSampleOperands(_ sample: String) throws -> PluralOperands {
    let parts = sample.split(separator: "c", omittingEmptySubsequences: false)
    guard parts.count == 1 || parts.count == 2 else { throw ConformanceError("Invalid CLDR sample \(sample)") }
    let exponent: Int?
    if parts.count == 2 {
        guard let value = Int(parts[1]), value >= 0 else { throw ConformanceError("Invalid compact CLDR sample \(sample)") }
        exponent = value
    } else { exponent = nil }
    return try PluralOperands(.decimal(ExactDecimal(String(parts[0]))), compactExponent: exponent)
}

private func pluralExample(_ value: JSONValue) throws -> (values: [String], infinite: Bool) {
    let fields = try value.checkedObject(at: "example", allowed: ["values", "infinite"])
    try fields.requireKeys(["values", "infinite"], at: "example")
    guard case .bool(let infinite) = try fields.value("infinite", at: "example") else { throw ConformanceError("Invalid example finiteness") }
    return (try pluralStrings(fields.value("values", at: "example"), path: "example.values"), infinite)
}
