import Foundation
import XCTest
@testable import Lokalized
import LokalizedConformanceSupport

final class ManifestPlanningTests: XCTestCase {
    func testStandalonePublicPlanningQualification() throws {
        XCTAssertEqual(try ConformanceRunner.manifestPlanningSelfTest(), 41)
    }
    func testRawManifestLocaleProjectionRetainsSyntaxVsRebuildabilityDistinction() throws {
        XCTAssertEqual(try ManifestLocale.normalizeTag("en-x-lvariant-NY"), "en-x-lvariant-NY")
        XCTAssertThrowsError(try LocaleTag("en-x-lvariant-NY"))
        XCTAssertEqual(ManifestLocale.primaryLanguage("und-aaland"), "")
        XCTAssertEqual(ManifestLocale.primaryLanguage("aa-Saaho"), "ssy")
        XCTAssertEqual(try ManifestLocale.normalizeTag("mo"), "mo")
        XCTAssertEqual(ManifestLocale.primaryLanguage("mo"), "ro")
    }
    func testFallbackElectionDoesNotUseArbitraryEquivalentOrder() {
        XCTAssertNil(ManifestLocale.electFallbackLocale("en-FONIPA", supported: ["en-fonipa", "en-Fonipa"], tiebreakerLocalesByLanguageCode: [:]))
        XCTAssertEqual(ManifestLocale.electFallbackLocale("en-FONIPA", supported: ["en-fonipa", "en-Fonipa"],
            tiebreakerLocalesByLanguageCode: ["en": ["en-fonipa", "en-Fonipa"]]), "en-fonipa")
        XCTAssertEqual(ManifestLocale.electFallbackLocale("en-Fonipa", supported: ["en-fonipa", "en-Fonipa"],
            tiebreakerLocalesByLanguageCode: ["en": ["en-fonipa", "en-Fonipa"]]), "en-Fonipa")
    }
}
