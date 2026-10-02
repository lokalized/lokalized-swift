import XCTest
@testable import Lokalized

final class PunycodeCodecTests: XCTestCase {
    func testIndependentKnownEncodingsAndScalarRoundTrips() throws {
        let pairs = [("bücher", "bcher-kva"), ("faß", "fa-hia"), ("☕", "53h"),
                     ("日本語", "wgv71a119e"), ("😀", "e28h"), ("é", "9ca"),
                     ("abc", "abc-"), ("", "")]
        for (text, encoded) in pairs {
            let scalars = text.unicodeScalars.map(\.value)
            XCTAssertEqual(PunycodeCodec.encode(scalars), encoded)
            XCTAssertEqual(PunycodeCodec.decode(Array(encoded.utf8)), scalars)
        }
        for values: [UInt32] in [[128, 128], [0x10FFFF, 0, 0x80], [0xD7FF, 0xE000], [97, 0x301, 98, 0x300]] {
            let encoded = try XCTUnwrap(PunycodeCodec.encode(values))
            XCTAssertEqual(PunycodeCodec.decode(Array(encoded.utf8)), values)
        }
        XCTAssertEqual(PunycodeCodec.decode(Array("BCHER-KVA".utf8)), "BüCHER".unicodeScalars.map(\.value))
    }
    func testInvalidScalarsDigitsAndOverflowFailClosed() {
        for input: [UInt32] in [[0xD800], [0xDFFF], [0x110000]] { XCTAssertNil(PunycodeCodec.encode(input)) }
        for input in ["!", "0", "999999999999999999999999999999999999999999999999999999999999999", "abc-!", "ib9b"] {
            XCTAssertNil(PunycodeCodec.decode(Array(input.utf8)), input)
        }
        XCTAssertNil(PunycodeCodec.decode([0xFF]))
    }
    func testPinnedArithmeticCeilingOnBothCodecDirections() throws {
        let scalar: UInt32 = 0x3134A
        let accepted = Array(repeating: UInt32(97), count: 10_660) + [scalar]
        let encoded = try XCTUnwrap(PunycodeCodec.encode(accepted))
        XCTAssertEqual(PunycodeCodec.decode(Array(encoded.utf8)), accepted)
        let refused = Array(repeating: UInt32(97), count: 10_661) + [scalar]
        XCTAssertNil(PunycodeCodec.encode(refused))
        // Independently encoded RFC payload exceeds the pinned arithmetic
        // ceiling, although its decoded code point itself is a valid scalar.
        XCTAssertNil(PunycodeCodec.decode(Array((String(repeating: "a", count: 10_661) + "-hh99146o").utf8)))
    }
}
