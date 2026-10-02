import CryptoKit
import Foundation
import Lokalized

public struct IDNANormalizationAuditReport: Encodable, Sendable {
    public let status: String
    public let unicodeVersion: String
    public let archiveSHA256: String
    public let officialRows: Int
    public let officialNFCEquations: Int
    public let identityScalarChecks: Int
    public let totalChecks: Int
    public let passed: Int
    public let failed: Int
    public let officialEquationIDSetSHA256: String
    public let identityScalarIDSetSHA256: String
    public let failures: [String]
}

public extension ConformanceRunner {
    /// Exercises only NFC: the five NFC equations in the official Unicode 17
    /// suite, followed by scalar identity outside Part 1. No host normalizer is
    /// used as either the implementation or the expected result.
    static func idnaNormalizationAudit(referenceDirectory: URL) throws -> IDNANormalizationAuditReport {
        let bytes = try boundedRead(referenceDirectory.appendingPathComponent("Unicode-17.0.0/NormalizationTest.txt"), maximumBytes: 4_194_304)
        func digest(_ value: Data) -> String { SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() }
        let archiveSHA = digest(bytes)
        guard archiveSHA == "5019ffd530751a741900c849c0e010332f142a3612234639bd200b82138a87db",
              let text = String(data: bytes, encoding: .utf8), text.hasPrefix("# NormalizationTest-17.0.0.txt\n") else {
            throw ConformanceError("Unicode 17 normalization archive digest or version differs")
        }

        var rowCount = 0, failed = 0, passed = 0, failures: [String] = []
        var officialIDs = Data(), identityIDs = Data()
        var part = "", part1: Set<UInt32> = []
        func observe(_ input: [UInt32], _ expected: [UInt32], id: String) {
            if PinnedNFC.normalize(input) == expected { passed += 1 }
            else { failed += 1; if failures.count < 32 { failures.append(id) } }
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].trimmingCharacters(in: .whitespaces)
            if content.isEmpty { continue }
            if content.hasPrefix("@") { part = content; continue }
            let fields = content.split(separator: ";", omittingEmptySubsequences: false)
            guard fields.count == 6, fields[5].trimmingCharacters(in: .whitespaces).isEmpty else { throw ConformanceError("Unicode normalization row shape differs") }
            let columns = try fields.prefix(5).map { field in
                try field.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { member in
                    guard let scalar = UInt32(member, radix: 16), scalar <= 0x10FFFF,
                          !(0xD800...0xDFFF).contains(scalar) else { throw ConformanceError("Unicode normalization scalar differs") }
                    return scalar
                }
            }
            if part == "@Part1" {
                guard columns[0].count == 1, part1.insert(columns[0][0]).inserted else { throw ConformanceError("Unicode normalization Part 1 inventory differs") }
            }
            rowCount += 1
            for column in 0..<5 {
                let id = String(format: "normalization:row:%05d:c%d", rowCount, column + 1)
                officialIDs.append(contentsOf: (id + "\n").utf8)
                observe(columns[column], column < 3 ? columns[1] : columns[3], id: id)
            }
        }
        guard rowCount == 20_034, part1.count == 17_086 else { throw ConformanceError("Unicode normalization inventory differs") }

        // The official requirement covers assigned characters. Checking every
        // remaining valid scalar also ensures unassigned scalars stay unchanged.
        var scalarChecks = 0
        for scalar: UInt32 in 0...0x10FFFF where !(0xD800...0xDFFF).contains(scalar) && !part1.contains(scalar) {
            let id = String(format: "normalization:identity:%06x", scalar)
            identityIDs.append(contentsOf: (id + "\n").utf8)
            observe([scalar], [scalar], id: id)
            scalarChecks += 1
        }
        guard scalarChecks == 1_094_978 else { throw ConformanceError("Unicode normalization identity inventory differs") }
        return .init(status: failed == 0 ? "passed" : "failed", unicodeVersion: "17.0.0", archiveSHA256: archiveSHA,
                     officialRows: rowCount, officialNFCEquations: rowCount * 5, identityScalarChecks: scalarChecks,
                     totalChecks: passed + failed, passed: passed, failed: failed,
                     officialEquationIDSetSHA256: digest(officialIDs), identityScalarIDSetSHA256: digest(identityIDs), failures: failures)
    }
}
