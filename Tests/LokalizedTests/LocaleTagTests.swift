import XCTest
import Foundation
import Lokalized
import LokalizedConformanceSupport

final class LocaleTagTests: XCTestCase {
    func testJDKProjectionAndCLDRAliasesAreSeparate() throws {
        let deprecated = try LocaleTag("mo-MD")
        XCTAssertEqual(deprecated.tag, "mo-MD")
        XCTAssertEqual(deprecated.language, "mo")
        XCTAssertEqual(deprecated.cldrCanonicalTag, "ro-MD")
        XCTAssertEqual(try LocaleTag("sh").tag, "sh")
        XCTAssertEqual(try LocaleTag("sh").cldrCanonicalTag, "sr-Latn")
        XCTAssertEqual(try LocaleTag("iw-IL").tag, "he-IL")
        XCTAssertEqual(try LocaleTag("iw-IL").language, "he")
        XCTAssertEqual(try LocaleTag("in").tag, "id")
        XCTAssertEqual(try LocaleTag("ji").tag, "yi")
    }

    func testProjectionDropsOnlyIllFormedSuffixWhileStrictInitializerRejectsIt() throws {
        for (input, expected) in [("en-", "en"), ("en-1-abc", "en"), ("en_US", "und"), ("!", "und"),
                                  ("", "und"), ("en-Latn-US-invalid-too-long", "en-Latn-US-invalid"), ("x", "und")] {
            XCTAssertEqual(LocaleTag.forLanguageTag(input).tag, expected)
            XCTAssertThrowsError(try LocaleTag(input)) { error in
                XCTAssertEqual((error as? LocaleTagError)?.kind, .malformedLanguageTag)
            }
        }
        XCTAssertEqual(try LocaleTag("x-private").tag, "x-private")
        XCTAssertEqual(try LocaleTag("zz").tag, "zz")
        XCTAssertFalse(try LocaleTag("zz").isKnownLanguageTag)
    }

    func testExtlangCollapseAndGrandfatheredReplacements() throws {
        XCTAssertEqual(try LocaleTag("ZH-CMN-HANS-CN").tag, "cmn-Hans-CN")
        XCTAssertEqual(try LocaleTag("en-abc-def-ghi-Cyrl-US-1996").language, "abc")
        let aliases = ["i-klingon": "tlh", "i-default": "en-x-i-default", "i-enochian": "x-i-enochian",
                       "zh-min": "nan-x-zh-min", "en-GB-oed": "en-GB-x-oed", "no-bok": "nb", "sgn-BE-FR": "sfb"]
        for (input, expected) in aliases { XCTAssertEqual(try LocaleTag(input).tag, expected) }
        XCTAssertEqual(LocaleTag.forLanguageTag("i-Klingon").tag, "und")
    }

    func testLocaleSeparatorsAndLenientUnicodeSubtagsMatchJava() throws {
        let malformed = "ji-\u{301}u"
        XCTAssertEqual(LocaleASCII.splitSubtags(malformed), ["ji", "\u{301}u"])
        XCTAssertEqual(LocaleTag.forLanguageTag(malformed).tag, "yi")
        XCTAssertThrowsError(try LocaleTag(malformed))

        XCTAssertEqual(CldrLocaleData.canonicalLanguageTag("in-Katn-fonipa-x"), "id-Katn-fonipa-x")
        XCTAssertEqual(CldrLocaleData.likelySubtagFor("in-Katn-fonipa-x"), "id-Katn-ID-fonipa")
        XCTAssertEqual(CldrLocaleData.canonicalLanguageTag("en-١٢٣"), "en-١٢٣")
        XCTAssertEqual(LocaleUnicodeTables.upper("aßé"), "ASSÉ")
        XCTAssertTrue(LocaleUnicodeTables.isDigit(0x0661))
        XCTAssertFalse(LocaleUnicodeTables.isDigit(0x2160))
    }

    func testUnicodeExtensionsSortAttributesAndKeywordsAndRetainFirstDuplicates() throws {
        XCTAssertEqual(try LocaleTag("en-US-u-nu-latn-ca-gregory").tag, "en-US-u-ca-gregory-nu-latn")
        XCTAssertEqual(try LocaleTag("en-u-zzz-aaa-zzz-nu-latn-ca-gregory").tag, "en-u-aaa-zzz-ca-gregory-nu-latn")
        XCTAssertEqual(try LocaleTag("en-u-ca-x1-ca-x2").tag, "en-u-ca-x1-x2")
        XCTAssertEqual(try LocaleTag("en-b-def-a-abc-b-ghi").tag, "en-a-abc-b-def")
        XCTAssertEqual(try LocaleTag("en-u-nu-latn-u-ca-gregory").tag, "en-u-nu-latn")
        let left = try LocaleTag("en-u-nu-latn-ca-gregory")
        let right = try LocaleTag("en-u-ca-gregory-nu-latn")
        XCTAssertEqual(left, right)
        XCTAssertEqual(left.hashValue, right.hashValue)
        XCTAssertEqual(left.extensions["u"], "ca-gregory-nu-latn")
    }

    func testVariantCaseAndLvariantLiftArePreservedInLocaleIdentity() throws {
        let lifted = try LocaleTag("en-US-x-lvariant-POSIX")
        let direct = try LocaleTag("en-US-POSIX")
        XCTAssertEqual(lifted.tag, "en-US-POSIX")
        XCTAssertEqual(lifted.variants, ["POSIX"])
        XCTAssertEqual(lifted, direct)
        XCTAssertNotEqual(lifted, try LocaleTag("en-US-posix"))
        XCTAssertEqual(lifted.cldrCanonicalTag, "en-US-posix")
        let privateLocale = try LocaleTag("en-US-x-custom-lvariant-POSIX")
        XCTAssertEqual(privateLocale.tag, "en-US-POSIX-x-custom")
        XCTAssertEqual(privateLocale.privateUse, ["custom"])
        XCTAssertEqual(privateLocale.extensions["x"], "custom")
        XCTAssertEqual(try LocaleTag("en-x-lvariant").privateUse, ["lvariant"])
    }

    func testCompatibilityLocalesAndRebuildabilityAreDifferentFromTagSyntax() throws {
        let japanese = try LocaleTag("ja-JP-x-lvariant-JP")
        XCTAssertEqual(japanese.tag, "ja-JP-u-ca-japanese-x-lvariant-JP")
        XCTAssertEqual(japanese.variants, ["JP"])
        XCTAssertEqual(japanese.extensions["u"], "ca-japanese")
        XCTAssertEqual(try LocaleTag("th-TH-x-lvariant-TH").tag, "th-TH-u-nu-thai-x-lvariant-TH")
        XCTAssertEqual(try LocaleTag("ja-JP-a-ab-x-lvariant-JP").tag, "ja-JP-a-ab-x-lvariant-JP")
        let norwegian = try LocaleTag("no-NO-x-lvariant-NY")
        XCTAssertEqual(norwegian.tag, "nn-NO")
        XCTAssertEqual(norwegian.language, "no")
        XCTAssertEqual(norwegian.variants, ["NY"])
        XCTAssertNotEqual(norwegian, try LocaleTag("nn-NO"))
        XCTAssertThrowsError(try LocaleTag("ja-JP-x-lvariant-jp")) { error in
            XCTAssertEqual((error as? LocaleTagError)?.kind, .malformedLocale)
            XCTAssertEqual((error as? LocaleTagError)?.message, "Locale 'ja_JP_jp' is not a well-formed IETF BCP 47 locale")
        }
        XCTAssertThrowsError(try LocaleTag("en-US-x-lvariant-NY"))
    }

    func testIdenticalRenderedTagsCanHaveDifferentLocaleIdentities() throws {
        let emptyLanguage = LocaleTag.forLanguageTag("und")
        let actualUnd = LocaleTag.forLanguageTag("UND")
        XCTAssertEqual(emptyLanguage.tag, "und")
        XCTAssertEqual(actualUnd.tag, "und")
        XCTAssertEqual(emptyLanguage.language, "")
        XCTAssertEqual(actualUnd.language, "und")
        XCTAssertNotEqual(emptyLanguage, actualUnd)
        XCTAssertEqual(Set([emptyLanguage, actualUnd]).count, 2)
        XCTAssertEqual(LocaleTag.forLanguageTag("zh-und"), actualUnd)
        XCTAssertEqual(LocaleTag.forLanguageTag("und-x-a").tag, "x-a")
        XCTAssertEqual(LocaleTag.forLanguageTag("UND-x-a").tag, "und-x-a")
    }

    func testCLDRCanonicalizationFixpointAndCompoundAliases() throws {
        let aliases = ["aa-Saaho": "ssy", "sh-BA-fonipa": "sr-Latn-BA-fonipa",
                       "sh-Cyrl-BA": "sr-Cyrl-BA", "en-Qaai": "en-Zinh", "el-polytoni": "el-polyton",
                       "hy-SU": "hy-AM", "ru-SU": "ru-RU", "en-Zzzz-ZZ": "en"]
        for (input, expected) in aliases {
            let locale = try LocaleTag(input)
            XCTAssertEqual(locale.cldrCanonicalTag, expected)
            XCTAssertEqual(LocaleTag.forLanguageTag(locale.cldrCanonicalTag).cldrCanonicalTag, expected)
        }
    }

    func testLikelySubtagsPreserveRequestedFieldsAndReturnFullTriples() throws {
        let cases = ["en": "en-Latn-US", "zh-TW": "zh-Hant-TW", "sr-Latn": "sr-Latn-RS", "und-Arab": "ar-Arab-EG",
                     "az-IR": "az-Arab-IR", "en-fonipa-u-ca-gregory": "en-Latn-US-fonipa", "zz-Arab": "zz-Arab-EG"]
        for (input, expected) in cases { XCTAssertEqual(try LocaleTag(input).likelySubtag, expected) }
        XCTAssertNil(try LocaleTag("x-private").likelySubtag)
        XCTAssertEqual(try LocaleTag("mo").likelySubtag, "ro-Latn-RO")
    }

    func testExplicitParentsScriptBoundariesAndNorwegianBridges() throws {
        XCTAssertEqual(try LocaleTag("en-AU").fallbackLocaleTags, ["en-AU", "en-001", "en"])
        XCTAssertEqual(try LocaleTag("es-AR").fallbackLocaleTags, ["es-AR", "es-419", "es"])
        XCTAssertEqual(try LocaleTag("sr-Latn-RS").fallbackLocaleTags, ["sr-Latn-RS", "sr-Latn"])
        XCTAssertEqual(try LocaleTag("zh-Hant-TW").fallbackLocaleTags, ["zh-Hant-TW", "zh-Hant"])
        XCTAssertEqual(try LocaleTag("no-NO").fallbackLocaleTags, ["no-NO", "no", "nb-NO", "nb"])
        XCTAssertEqual(try LocaleTag("nb-NO").fallbackLocaleTags, ["nb-NO", "nb", "no", "no-NO"])
        XCTAssertEqual(try LocaleTag("mo-MD").fallbackLocaleTags, ["mo-MD", "mo", "ro-MD", "ro"])
        XCTAssertFalse(try LocaleTag("az-Arab").fallbackLocaleTags.contains("root"))
    }

    func testKnownTagsAndRTLUsePinnedValidityAndScriptData() throws {
        XCTAssertTrue(try LocaleTag("he").isRightToLeft)
        XCTAssertFalse(try LocaleTag("he-Latn").isRightToLeft)
        XCTAssertTrue(try LocaleTag("en-Arab").isRightToLeft)
        XCTAssertTrue(try LocaleTag("az-IR").isRightToLeft)
        XCTAssertFalse(try LocaleTag("x-private").isRightToLeft)
        XCTAssertTrue(try LocaleTag("de-1901").isKnownLanguageTag)
        XCTAssertTrue(try LocaleTag("en-Qaai").isKnownLanguageTag)
        XCTAssertFalse(try LocaleTag("en-zzzzzzzz").isKnownLanguageTag)
        XCTAssertTrue(try LocaleTag("x-private").isKnownLanguageTag)
        XCTAssertTrue(try LocaleTag("und").hasUndeterminedLanguage)
    }

    func testLocaleTagsAreImmutableAndSendable() throws {
        func checked<T: Sendable>(_ value: T) -> T { value }
        let locale = checked(try LocaleTag("EN-latn-us-u-nu-latn-X-Custom"))
        XCTAssertEqual(locale.tag, "en-Latn-US-u-nu-latn-x-custom")
        XCTAssertEqual(locale.language, "en")
        XCTAssertEqual(locale.script, "Latn")
        XCTAssertEqual(locale.region, "US")
        XCTAssertEqual(locale.privateUse, ["custom"])
    }

    func testFilenameRecognitionIsDifferentFromExplicitLocaleConstruction() throws {
        XCTAssertTrue(JDKLocaleTag.isCatalogLanguageTag("mo-MD"))
        XCTAssertTrue(JDKLocaleTag.isCatalogLanguageTag("und"))
        XCTAssertTrue(JDKLocaleTag.isCatalogLanguageTag("x-private"))
        XCTAssertTrue(JDKLocaleTag.isCatalogLanguageTag("i-klingon"))
        XCTAssertFalse(JDKLocaleTag.isCatalogLanguageTag("zz"))
        XCTAssertFalse(JDKLocaleTag.isCatalogLanguageTag("de.txt"))
        XCTAssertFalse(JDKLocaleTag.isCatalogLanguageTag("aa-Saaho-ER"))
        XCTAssertFalse(JDKLocaleTag.isCatalogLanguageTag("en-1-abc"))
        // Filename recognition uses setLanguageTag rather than the additional
        // setLocale rebuild guard applied to an explicitly supplied locale.
        XCTAssertTrue(JDKLocaleTag.isCatalogLanguageTag("ja-JP-x-lvariant-jp"))
        XCTAssertThrowsError(try LocaleTag("ja-JP-x-lvariant-jp"))
    }

    func testCompleteLocaleDataAndActualJavaGoldenAudit() throws {
        let report = try ConformanceRunner.localeDataAudit(referenceDirectory: referenceDirectory)
        XCTAssertEqual(report.status, "passed")
        XCTAssertEqual(report.compiledTableRows, 18_675)
        XCTAssertEqual(report.projectionCases, 12_560)
        XCTAssertEqual(report.observationsPerCase, 21)
        XCTAssertEqual(report.checks, 263_771)
        XCTAssertEqual(report.failedChecks, 0)
        XCTAssertTrue(report.failures.isEmpty)
    }

    func testLocaleAuditRefusesTamperedExpectedData() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("lokalized-locale-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for name in ["cldr-locale-data.json", "locale-goldens.json"] {
            try FileManager.default.copyItem(at: referenceDirectory.appendingPathComponent(name), to: temporary.appendingPathComponent(name))
        }
        let target = temporary.appendingPathComponent("locale-goldens.json")
        var bytes = try Data(contentsOf: target)
        bytes.append(32)
        try bytes.write(to: target)
        XCTAssertThrowsError(try ConformanceRunner.localeDataAudit(referenceDirectory: temporary)) { error in
            XCTAssertEqual(String(describing: error), "Locale reference digest mismatch: locale-goldens.json")
        }
    }

    private var referenceDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Reference")
    }
}
