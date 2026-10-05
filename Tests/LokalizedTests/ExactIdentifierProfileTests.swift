import CryptoKit
import Foundation
import Lokalized
import XCTest

final class ExactIdentifierProfileTests: XCTestCase {
    func testSharedExactIdentifierProfile() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Reference/exact-identifier-v1.json")
        let data = try Data(contentsOf: source)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "3b20ec306ec5da919909e28a6db04085ad4cf9133d76adb6cf87f3631ee72e6f")
        let profile = try JSONDecoder().decode(ExactIdentifierProfile.self, from: data)
        XCTAssertEqual(profile.formatVersion, 1)
        XCTAssertEqual(profile.profileID, "exact-identifier-v1")
        XCTAssertEqual(profile.profileVersion, "1.0.0")
        XCTAssertEqual(profile.cases.count, 15)
        for row in profile.cases { try run(row, fixture: profile.fixture) }
    }

    private func run(_ row: ExactIdentifierRow, fixture: ExactIdentifierFixture) throws {
        let source = try XCTUnwrap(fixture.catalogs[row.catalog], row.id)
        if row.operation == "parse" {
            XCTAssertEqual(row.expected.status, "refused", row.id)
            let expectedMessage = try XCTUnwrap(row.expected.message, row.id)
            XCTAssertThrowsError(try LocalizedStringLoader.parse(source, locale: fixture.locale, source: row.id)) { error in
                guard let refusal = error as? StringsParseError else { return XCTFail("\(row.id): Expected StringsParseError: \(error)") }
                XCTAssertEqual(Array(refusal.message.utf16), Array(expectedMessage.utf16), row.id)
            }
            return
        }
        let locale = try LocaleTag(fixture.locale)
        let parsed = try LocalizedStringLoader.parse(source, locale: fixture.locale)
        let catalog = LocalizedCatalog(strings: parsed.strings)
        let strings = try DefaultStrings(configuration: StringsConfiguration(
            localizedStringSupplier: { [locale: catalog] },
            localeSupplier: { _ in locale }, fallbackLocale: locale,
            translationFailureHandler: .returnKey()))
        let key = try XCTUnwrap(row.key, row.id)
        let values = PlaceholderValues(entries: (row.values ?? []).map { (ExactString($0.name), .text($0.text)) })
        let result = try strings.getResult(ExactString(key), placeholders: values)
        XCTAssertEqual(result.status.rawValue, row.expected.status, row.id)
        XCTAssertEqual(Array(result.key.string.utf16), Array(try XCTUnwrap(row.expected.key, row.id).utf16), row.id)
        XCTAssertEqual(Array(result.translation.utf16), Array(try XCTUnwrap(row.expected.translation, row.id).utf16), row.id)
        XCTAssertEqual(result.attemptedLocales.map(\.tag), row.expected.attemptedLocales, row.id)
    }
}

private struct ExactIdentifierProfile: Decodable {
    let formatVersion: Int
    let profileID: String
    let profileVersion: String
    let fixture: ExactIdentifierFixture
    let cases: [ExactIdentifierRow]
}
private struct ExactIdentifierFixture: Decodable {
    let locale: String
    let catalogs: [String: String]
}
private struct ExactIdentifierRow: Decodable {
    let id: String
    let operation: String
    let catalog: String
    let key: String?
    let values: [ExactIdentifierValue]?
    let expected: ExactIdentifierExpected
}
private struct ExactIdentifierValue: Decodable {
    let name: String
    let text: String
}
private struct ExactIdentifierExpected: Decodable {
    let status: String
    let message: String?
    let key: String?
    let translation: String?
    let attemptedLocales: [String]?
}
