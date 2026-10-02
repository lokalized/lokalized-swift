import Foundation
import XCTest
@testable import Lokalized
@testable import LokalizedConformanceSupport

final class CatalogIdentityTests: XCTestCase {
    func testKnownAnswersProjectionAndExactUnicodeIdentity() throws {
        XCTAssertEqual(try ManifestIdentityQualification.runNative(), 19)
    }

    func testIdentityInputIsIndependentOfManifestTagRecognition() throws {
        let input = CatalogIdentityInputV1(catalogVersion: "publication", resolvedFallbackLocale: "custom-fallback",
            localeToSha256: ["not a locale": String(repeating: "1", count: 64)],
            tiebreakerLocalesByLanguageCode: ["arbitrary": ["second", "first"]])
        let text = String(decoding: try LocalizedStringLoader.catalogIdentityBytes(input), as: UTF8.self)
        XCTAssertTrue(text.contains("\"not a locale\""))
        XCTAssertTrue(text.contains("[\"second\",\"first\"]"))
    }
}
