import CryptoKit
import Foundation
import Lokalized

/// Developer-only observations from the frozen Java source and pinned JDK.
/// Neither this archive nor its parser is used by the production library.
public struct LocaleDataAuditReport: Encodable, Sendable {
    public let status: String
    public let cldrVersion: String
    public let localeSourceSha256: String
    public let goldenSha256: String
    public let javaCorpusCommit: String
    public let dataFingerprint: String
    public let tableFormat: String
    public let generatedSwiftBytes: Int
    public let localeSourceBytes: Int
    public let goldenBytes: Int
    public let compiledTableRows: Int
    public let projectionCases: Int
    public let observationsPerCase: Int
    public let checks: Int
    public let failedChecks: Int
    public let failures: [String]
}

private let localeGoldenSHA = "40e876c0c61bdc4f9e0bbe51d95eb1462b503acecb97ace785f79b33f8be8e7d"
private let localeSourceSHA = "6241d8889b507a6edc0d6dae7e7812c372b62208ba8649701a819de877eade93"
private let localeObservationFields = [
    "tag", "language", "script", "region", "variant", "extensions", "javaIdentifier", "rebuildable",
    "fullSyntax", "strict", "catalogTag", "canonicalRaw", "canonicalProjected", "likelyRaw", "likelyProjected",
    "likelyLanguageScript", "fallback", "knownRaw", "undeterminedRaw", "privateRaw", "rtl"
]

public extension ConformanceRunner {
    /// Compares every compiled metadata row with its source and 263,760 actual
    /// Java/JDK observations. Expected behavior never feeds production lookup.
    static func localeDataAudit(referenceDirectory: URL) throws -> LocaleDataAuditReport {
        func frozen(_ name: String, sha: String) throws -> Data {
            let data = try boundedRead(referenceDirectory.appendingPathComponent(name), maximumBytes: 4_194_304)
            guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha else {
                throw ConformanceError("Locale reference digest mismatch: \(name)")
            }
            return data
        }
        let sourceBytes = try frozen("cldr-locale-data.json", sha: localeSourceSHA)
        let goldenBytes = try frozen("locale-goldens.json", sha: localeGoldenSHA)
        let source = try JSONReader.parse(sourceBytes, limits: corpusLimits).checkedObject(at: "locale source", allowed: [
            "aliases", "cldrVersion", "formatVersion", "likelySubtags", "parentLocales", "rightToLeftScripts", "validity"
        ])
        let golden = try JSONReader.parse(goldenBytes, limits: corpusLimits).checkedObject(at: "locale observations", allowed: [
            "formatVersion", "inputs", "observations", "fields", "javaCorpusCommit", "jdkReleaseSha256",
            "javaSourceHashes", "localeSourceSha256", "oracleSourceSha256"
        ])
        let commit = "63b63e47c982f7a87873c52ac2289cc0392f3329"
        guard source["formatVersion"].numberLiteral == "1", golden["formatVersion"].numberLiteral == "1",
              try source.string("cldrVersion", at: "locale source") == "48.2",
              try golden.string("javaCorpusCommit", at: "locale observations") == commit,
              try golden.string("localeSourceSha256", at: "locale observations") == localeSourceSHA,
              try localeStrings(golden.value("fields", at: "locale observations")) == localeObservationFields,
              LocaleTables.cldrVersion == "48.2", LocaleTables.sourceSha256 == localeSourceSHA,
              LocaleTables.dataFingerprint == BuildMetadata.current.dataFingerprint else {
            throw ConformanceError("Locale reference/compiled provenance differs")
        }
        var checks = 0, failed = 0, failures: [String] = [], tableRows = 0
        func expect(_ condition: Bool, _ detail: String) {
            checks += 1
            if !condition { failed += 1; if failures.count < 64 { failures.append(detail) } }
        }
        func pairs(_ reference: JSONValue, _ compiled: [String: String], _ name: String) throws {
            var values: [String: String] = [:]
            for row in try localeArray(reference) {
                let fields = try row.checkedObject(at: name, allowed: ["from", "to"])
                let key = try fields.string("from", at: name), value = try fields.string("to", at: name)
                guard values.updateValue(value, forKey: LocaleASCII.lower(key)) == nil else {
                    throw ConformanceError("Duplicate reference locale key in \(name)")
                }
            }
            tableRows += values.count
            expect(values == compiled, "complete compiled \(name)")
        }
        func values(_ reference: JSONValue, _ compiled: Set<String>, _ name: String) throws {
            let rows = try localeStrings(reference).map(LocaleASCII.lower)
            guard Set(rows).count == rows.count else { throw ConformanceError("Duplicate reference locale value in \(name)") }
            tableRows += rows.count
            expect(Set(rows) == compiled, "complete compiled \(name)")
        }
        let aliases = try source.value("aliases", at: "locale source").checkedObject(at: "aliases", allowed: ["language", "region", "script", "variant"])
        try pairs(aliases.value("language", at: "aliases"), LocaleTables.languageAliases, "language aliases")
        try pairs(aliases.value("region", at: "aliases"), LocaleTables.regionAliases, "region aliases")
        try pairs(aliases.value("script", at: "aliases"), LocaleTables.scriptAliases, "script aliases")
        try pairs(aliases.value("variant", at: "aliases"), LocaleTables.variantAliases, "variant aliases")
        try pairs(source.value("likelySubtags", at: "locale source"), LocaleTables.likelySubtags, "likely subtags")
        try pairs(source.value("parentLocales", at: "locale source"), LocaleTables.parentLocales, "parent locales")
        let validity = try source.value("validity", at: "locale source").checkedObject(at: "validity", allowed: ["languages", "regions", "scripts", "variants"])
        try values(validity.value("languages", at: "validity"), LocaleTables.validLanguages, "valid languages")
        try values(validity.value("regions", at: "validity"), LocaleTables.validRegions, "valid regions")
        try values(validity.value("scripts", at: "validity"), LocaleTables.validScripts, "valid scripts")
        try values(validity.value("variants", at: "validity"), LocaleTables.validVariants, "valid variants")
        try values(source.value("rightToLeftScripts", at: "locale source"), LocaleTables.rightToLeftScripts, "RTL scripts")
        let inputs = try localeStrings(golden.value("inputs", at: "locale observations"))
        let outputs = try localeStrings(golden.value("observations", at: "locale observations"))
        guard inputs.count == 12_560, outputs.count == inputs.count, tableRows == 18_675 else {
            throw ConformanceError("Incomplete locale qualification inventory")
        }
        for (input, encoded) in zip(inputs, outputs) {
            let expected = try encoded.split(separator: "\t", omittingEmptySubsequences: false).map { field -> String in
                guard let data = Data(base64Encoded: String(field)), let text = String(data: data, encoding: .utf8) else {
                    throw ConformanceError("Malformed locale golden observation")
                }
                return text
            }
            let actual = localeObservations(input)
            guard expected.count == localeObservationFields.count, actual.count == expected.count else {
                throw ConformanceError("Incomplete locale observation fields")
            }
            for index in expected.indices {
                expect(actual[index] == expected[index], "\(input) \(localeObservationFields[index]): expected '\(expected[index])', observed '\(actual[index])'")
            }
        }
        guard checks == 263_771 else { throw ConformanceError("Incomplete locale qualification traversal") }
        return .init(status: failed == 0 ? "passed" : "failed", cldrVersion: "48.2", localeSourceSha256: localeSourceSHA,
                     goldenSha256: localeGoldenSHA, javaCorpusCommit: commit, dataFingerprint: LocaleTables.dataFingerprint,
                     tableFormat: "packed-text-maps-v1", generatedSwiftBytes: 254_321, localeSourceBytes: sourceBytes.count,
                     goldenBytes: goldenBytes.count, compiledTableRows: tableRows, projectionCases: inputs.count,
                     observationsPerCase: localeObservationFields.count, checks: checks, failedChecks: failed, failures: failures)
    }
}

private func localeArray(_ value: JSONValue) throws -> [JSONValue] {
    guard case .array(let rows) = value else { throw ConformanceError("Expected locale reference array") }
    return rows
}
private func localeStrings(_ value: JSONValue) throws -> [String] {
    try localeArray(value).map {
        guard case .string(let text) = $0 else { throw ConformanceError("Expected locale reference string") }
        return text
    }
}
private func localeObservations(_ text: String) -> [String] {
    let locale = LocaleTag.forLanguageTag(text)
    let full = JDKLocaleTag.parse(text).wellFormed
    let rebuildable = (try? JDKLocaleTag.requireWellFormed(locale, description: "Locale")) != nil
    return [locale.tag, locale.language, locale.script, locale.region, locale.variants.joined(separator: "_"),
            locale.extensions.keys.sorted().map { $0 + "-" + locale.extensions[$0]! }.joined(separator: "-"),
            locale.javaIdentifier, String(rebuildable), String(full), String((try? LocaleTag(text)) != nil),
            String(JDKLocaleTag.isCatalogLanguageTag(text)), CldrLocaleData.canonicalLanguageTag(text),
            locale.cldrCanonicalTag, CldrLocaleData.likelySubtagFor(text) ?? "<nil>", locale.likelySubtag ?? "<nil>",
            CldrLocaleData.languageScriptForLikelySubtag(text) ?? "<nil>", locale.fallbackLocaleTags.joined(separator: "|"),
            String(CldrLocaleData.isKnownLanguageTag(text)), String(CldrLocaleData.hasUndeterminedLanguage(text)),
            String(CldrLocaleData.isPrivateUseLanguageTag(text)), String(locale.isRightToLeft)]
}

/// Public API checks usable by standalone consumers without XCTest or files.
enum LocaleDataQualification {
    static func run() throws -> Int {
        var checks = 0
        func expect(_ condition: @autoclosure () throws -> Bool, _ detail: String) throws {
            guard try condition() else { throw ConformanceError("Locale qualification: \(detail)") }
            checks += 1
        }
        func refuse(_ text: String, _ kind: LocaleTagError.Kind) throws {
            do { _ = try LocaleTag(text) }
            catch let error as LocaleTagError { try expect(error.kind == kind, "typed refusal \(text)"); return }
            throw ConformanceError("Locale qualification accepted invalid input: \(text)")
        }
        let deprecated = try LocaleTag("mo-MD")
        try expect(deprecated.tag == "mo-MD" && deprecated.language == "mo", "JDK identity precedes CLDR aliases")
        try expect(deprecated.cldrCanonicalTag == "ro-MD", "separate CLDR alias")
        try expect(try LocaleTag("iw-IL").tag == "he-IL", "JDK historical language spelling")
        try expect(try LocaleTag("sh").tag == "sh" && LocaleTag("sh").cldrCanonicalTag == "sr-Latn", "compound CLDR replacement")
        try expect(try LocaleTag("zh-cmn-Hans-CN").tag == "cmn-Hans-CN", "extlang replaces primary language")
        try expect(try LocaleTag("i-default").tag == "en-x-i-default", "grandfathered replacement retains private use")
        try expect(try LocaleTag("zh-min").tag == "nan-x-zh-min", "grandfathered language and private use")
        try expect(LocaleTag.forLanguageTag("i-Klingon").tag == "und", "JDK grandfathered lookup uses ASCII casing")
        try expect(LocaleTag.forLanguageTag("en-1-abc").tag == "en", "lenient suffix projection")
        try refuse("en-1-abc", .malformedLanguageTag)
        try refuse("", .malformedLanguageTag)
        try expect(try LocaleTag("zz").tag == "zz" && !LocaleTag("zz").isKnownLanguageTag, "unknown full-syntax tags remain constructible")
        let lowerUnd = LocaleTag.forLanguageTag("und"), upperUnd = LocaleTag.forLanguageTag("UND")
        try expect(lowerUnd.tag == upperUnd.tag && lowerUnd != upperUnd, "rendered tag does not define locale identity")
        try expect(Set([lowerUnd, upperUnd]).count == 2, "hash retains underlying locale identity")
        try expect(LocaleTag.forLanguageTag("zh-und") == upperUnd, "extlang und differs from root identity")
        try expect(LocaleTag.forLanguageTag("und-x-a").tag == "x-a", "root tag omits language before private use")
        try expect(try LocaleTag("en-u-nu-latn-ca-gregory").tag == "en-u-ca-gregory-nu-latn", "Unicode keyword ordering")
        try expect(try LocaleTag("en-u-zzz-aaa-zzz-ca-gregory").tag == "en-u-aaa-zzz-ca-gregory", "Unicode attribute ordering and deduplication")
        try expect(try LocaleTag("en-u-ca-x1-ca-x2").tag == "en-u-ca-x1-x2", "duplicate Unicode keys preserve JDK projection")
        try expect(try LocaleTag("en-b-def-a-abc-b-ghi").tag == "en-a-abc-b-def", "first singleton wins and singleton ordering")
        let direct = try LocaleTag("en-US-POSIX"), lifted = try LocaleTag("en-US-x-lvariant-POSIX")
        try expect(direct == lifted && direct.hashValue == lifted.hashValue, "lvariant lift identity")
        try expect(try lifted != LocaleTag("en-US-posix"), "variant case is significant in locale identity")
        try expect(try LocaleTag("en-US-x-custom-lvariant-POSIX").privateUse == ["custom"], "lvariant suffix excluded from surviving private use")
        try expect(try LocaleTag("ja-JP-x-lvariant-JP").tag == "ja-JP-u-ca-japanese-x-lvariant-JP", "Japanese compatibility locale")
        try expect(try LocaleTag("th-TH-x-lvariant-TH").tag == "th-TH-u-nu-thai-x-lvariant-TH", "Thai compatibility locale")
        try expect(try LocaleTag("no-NO-x-lvariant-NY").tag == "nn-NO" && LocaleTag("no-NO-x-lvariant-NY").language == "no", "Norwegian rendered identity distinction")
        try refuse("ja-JP-x-lvariant-jp", .malformedLocale)
        try refuse("en-US-x-lvariant-NY", .malformedLocale)
        try expect(try LocaleTag("aa-Saaho").cldrCanonicalTag == "ssy", "full compound alias")
        try expect(try LocaleTag("sh-Cyrl-BA").cldrCanonicalTag == "sr-Cyrl-BA", "explicit script survives language alias")
        try expect(try LocaleTag("hy-SU").cldrCanonicalTag == "hy-AM" && LocaleTag("ru-SU").cldrCanonicalTag == "ru-RU", "region alias uses likely language region")
        try expect(try LocaleTag("en-Qaai").cldrCanonicalTag == "en-Zinh", "script alias")
        try expect(try LocaleTag("el-polytoni").cldrCanonicalTag == "el-polyton", "variant alias")
        try expect(try LocaleTag("en-Zzzz-ZZ").cldrCanonicalTag == "en", "unknown script and region sentinels")
        try expect(try LocaleTag("zh-TW").likelySubtag == "zh-Hant-TW", "likely subtags preserve explicit region")
        try expect(try LocaleTag("sr-Latn").likelySubtag == "sr-Latn-RS", "likely subtags preserve explicit script")
        try expect(try LocaleTag("en-fonipa-u-ca-gregory").likelySubtag == "en-Latn-US-fonipa", "likely subtags retain variants and remove extensions")
        try expect(try LocaleTag("x-private").likelySubtag == nil, "private-use likely lookup has no language")
        try expect(try LocaleTag("en-AU").fallbackLocaleTags == ["en-AU", "en-001", "en"], "explicit parent before truncation")
        try expect(try LocaleTag("sr-Latn-RS").fallbackLocaleTags == ["sr-Latn-RS", "sr-Latn"], "script boundary stops fallback")
        try expect(try LocaleTag("nb-NO").fallbackLocaleTags == ["nb-NO", "nb", "no", "no-NO"], "Norwegian parent and bridge order")
        try expect(deprecated.fallbackLocaleTags == ["mo-MD", "mo", "ro-MD", "ro"], "requested and canonical parent chains")
        try expect(try LocaleTag("he").isRightToLeft && !LocaleTag("he-Latn").isRightToLeft, "explicit script overrides likely RTL")
        try expect(try LocaleTag("az-IR").isRightToLeft && LocaleTag("en-Arab").isRightToLeft, "likely and explicit RTL scripts")
        try expect(try LocaleTag("de-1901").isKnownLanguageTag && !LocaleTag("en-zzzzzzzz").isKnownLanguageTag, "pinned variant validity")
        return checks
    }
}
