import XCTest
import LokalizedConformanceSupport

final class TranslationOptionTests: XCTestCase {
    func testNegotiatedOptionsPreserveDiagnosticAndFailureContracts() throws {
        XCTAssertEqual(try ConformanceRunner.translationOptionSelfTest(), 37)
    }
}
