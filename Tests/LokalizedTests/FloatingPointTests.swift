import Foundation
import XCTest
@testable import Lokalized

final class FloatingPointTests: XCTestCase {
    func testSpecialValuesAndSignedZero() {
        for (value, expected) in [(Double.zero, "0.0"), (-Double.zero, "-0.0"),
                                  (.infinity, "Infinity"), (-.infinity, "-Infinity"), (.nan, "NaN")] {
            XCTAssertEqual(JavaFloatingPoint.decimalString(value), expected)
            XCTAssertEqual(JavaFloatingPoint.render(value), expected)
        }
        for (value, expected) in [(Float.zero, "0.0"), (-Float.zero, "-0.0"),
                                  (.infinity, "Infinity"), (-.infinity, "-Infinity"), (.nan, "NaN")] {
            XCTAssertEqual(JavaFloatingPoint.decimalString(value), expected)
            XCTAssertEqual(JavaFloatingPoint.render(value), expected)
        }
        XCTAssertEqual(JavaFloatingPoint.render(Double(bitPattern: 0xfff0000000000001)), "NaN")
        XCTAssertEqual(JavaFloatingPoint.render(Float(bitPattern: 0xff800001)), "NaN")
    }

    func testFloatWidthAndFormattingThresholds() {
        let single = Float(bitPattern: 0x3dcccccd)
        XCTAssertEqual(JavaFloatingPoint.render(single), "0.1")
        XCTAssertEqual(JavaFloatingPoint.render(Double(single)), "0.10000000149011612")
        let cases: [(Double, String)] = [
            (0.001, "0.001"), (0.0001, "1.0E-4"), (1_000_000, "1000000.0"),
            (10_000_000, "1.0E7"), (1, "1.0"), (123.25, "123.25"), (1e23, "1.0E23")
        ]
        for (value, expected) in cases { XCTAssertEqual(JavaFloatingPoint.render(value), expected) }
    }

    func testTinySubnormalsAndExactClosestDecimalTies() {
        // Java's length-one rule also considers length-two candidates: 4.9E-324,
        // rather than 5.0E-324, is closest to the smallest binary64 value.
        XCTAssertEqual(JavaFloatingPoint.render(Double(bitPattern: 1)), "4.9E-324")
        XCTAssertEqual(JavaFloatingPoint.render(Double(bitPattern: 2)), "9.9E-324")
        XCTAssertEqual(JavaFloatingPoint.render(Float(bitPattern: 1)), "1.4E-45")
        XCTAssertEqual(JavaFloatingPoint.render(Float(bitPattern: 2)), "2.8E-45")
        // Exact binary .25/.75 values admit both adjacent one-place decimals;
        // equal distances choose the even decimal significand.
        XCTAssertEqual(JavaFloatingPoint.render(Float(bitPattern: 0x4a000001)), "2097152.2")
        XCTAssertEqual(JavaFloatingPoint.render(Float(bitPattern: 0x4a000003)), "2097152.8")
        XCTAssertEqual(JavaFloatingPoint.render(Double(bitPattern: 0x4300000000000002)), "5.629499534213122E14")
        XCTAssertEqual(JavaFloatingPoint.render(Double(bitPattern: 0x4300000000000006)), "5.629499534213128E14")
    }

    func testIndependentPinnedJDKBitGoldensAndRoundTrips() throws {
        struct Entry: Decodable { let width: String; let bits: String; let decimal: String }
        struct JDK: Decodable { let javaVersion: String; let releaseSHA256: String }
        struct Archive: Decodable { let formatVersion: Int; let jdk: JDK; let samples: [Entry] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Reference/floating-point-goldens.json"))
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        XCTAssertEqual(archive.formatVersion, 1)
        XCTAssertEqual(archive.jdk.javaVersion, "21.0.11")
        XCTAssertEqual(archive.jdk.releaseSHA256, "31c8dd26f07b2bd2c394663b57a93879ea139f525c76c730b13956890c151239")
        XCTAssertEqual(archive.samples.count, 1592)
        var floats = 0
        var doubles = 0
        for entry in archive.samples {
            switch entry.width {
            case "float":
                let bits = try XCTUnwrap(UInt32(entry.bits, radix: 16))
                let value = Float(bitPattern: bits)
                let actual = JavaFloatingPoint.decimalString(value)
                XCTAssertEqual(actual, entry.decimal, "float \(entry.bits)")
                XCTAssertEqual(JavaFloatingPoint.render(value), actual)
                if value.isFinite { XCTAssertEqual(try XCTUnwrap(Float(actual)).bitPattern, bits) }
                floats += 1
            case "double":
                let bits = try XCTUnwrap(UInt64(entry.bits, radix: 16))
                let value = Double(bitPattern: bits)
                let actual = JavaFloatingPoint.decimalString(value)
                XCTAssertEqual(actual, entry.decimal, "double \(entry.bits)")
                XCTAssertEqual(JavaFloatingPoint.render(value), actual)
                if value.isFinite { XCTAssertEqual(try XCTUnwrap(Double(actual)).bitPattern, bits) }
                doubles += 1
            default: XCTFail("Unknown pinned floating width: \(entry.width)")
            }
        }
        XCTAssertEqual(floats, 782)
        XCTAssertEqual(doubles, 810)
    }
}
