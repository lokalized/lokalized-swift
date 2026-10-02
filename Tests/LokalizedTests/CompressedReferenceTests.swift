import Foundation
import XCTest
@testable import LokalizedConformanceSupport

final class CompressedReferenceTests: XCTestCase {
    // Independently encoded by Python's stdlib gzip: 131,073 ASCII 'a' bytes.
    // This spans more than two decoder output chunks and has a valid CRC/size.
    private var multichunk: Data {
        Data(base64Encoded: "H4sIAAAAAAAC/+3BMQEAAADCoKzrX8LHGEABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA3AC+GaTOAQACAA==")!
    }

    private func withArchive(_ bytes: Data, _ body: (URL) throws -> Void) throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = scratch.appendingPathComponent("fixture.json.gz")
        try bytes.write(to: file)
        try body(file)
    }

    func testExactBudgetsAcrossMultipleChunksAndOneByteOverflows() throws {
        let bytes = multichunk
        try withArchive(bytes) { file in
            XCTAssertEqual(try ConformanceRunner.boundedGzipRead(file, maximumCompressedBytes: bytes.count,
                                                                 maximumDecodedBytes: 131_073), Data(repeating: 97, count: 131_073))
            XCTAssertThrowsError(try ConformanceRunner.boundedGzipRead(file, maximumCompressedBytes: bytes.count - 1,
                                                                        maximumDecodedBytes: 131_073)) {
                XCTAssertEqual(($0 as? ConformanceError)?.description, "Reference file exceeds byte budget: fixture.json.gz")
            }
            XCTAssertThrowsError(try ConformanceRunner.boundedGzipRead(file, maximumCompressedBytes: bytes.count,
                                                                        maximumDecodedBytes: 131_072)) {
                XCTAssertEqual(($0 as? ConformanceError)?.description, "Decoded reference exceeds byte budget: fixture.json.gz")
            }
        }
    }

    func testEmptyGzipMemberAtZeroDecodedBudget() throws {
        let bytes = try XCTUnwrap(Data(base64Encoded: "H4sIAAAAAAAC/wMAAAAAAAAAAAA="))
        try withArchive(bytes) { file in
            XCTAssertEqual(try ConformanceRunner.boundedGzipRead(file, maximumCompressedBytes: bytes.count,
                                                                 maximumDecodedBytes: 0), Data())
        }
    }

    func testTruncatedMembersAndDamagedHeaderCRCAndSizeAreRefused() throws {
        let bytes = multichunk
        var header = bytes, crc = bytes, size = bytes
        header[0] ^= 1; crc[crc.count - 8] ^= 1; size[size.count - 4] ^= 1
        for invalid in [Data(), Data(bytes.prefix(4)), Data(bytes.dropLast()), header, crc, size] {
            try withArchive(invalid) { file in
                XCTAssertThrowsError(try ConformanceRunner.boundedGzipRead(file, maximumCompressedBytes: 1_024,
                                                                            maximumDecodedBytes: 131_073)) {
                    XCTAssertEqual(($0 as? ConformanceError)?.description, "Compressed reference is invalid or truncated: fixture.json.gz")
                }
            }
        }
    }

    func testTrailingBytesAndConcatenatedMembersAreRefused() throws {
        for invalid in [multichunk + Data([32]), multichunk + multichunk] {
            try withArchive(invalid) { file in
                XCTAssertThrowsError(try ConformanceRunner.boundedGzipRead(file, maximumCompressedBytes: 1_024,
                                                                            maximumDecodedBytes: 262_146)) {
                    XCTAssertEqual(($0 as? ConformanceError)?.description, "Compressed reference has trailing data: fixture.json.gz")
                }
            }
        }
    }

    func testPlaintextAndRawDeflateAreRefused() throws {
        for invalid in [Data("{}\n".utf8), Data(multichunk.dropFirst(10).dropLast(8))] {
            try withArchive(invalid) { file in
                XCTAssertThrowsError(try ConformanceRunner.boundedGzipRead(file, maximumCompressedBytes: 1_024,
                                                                            maximumDecodedBytes: 131_073))
            }
        }
    }
}
