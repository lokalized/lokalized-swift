import CryptoKit
import Foundation
import Lokalized

public struct RuntimeAdapterPendingGuard: Encodable, Sendable {
    public let category: String
    public let inputPath: String
    public let evidence: String
}

public struct RuntimeAdapterPendingCase: Encodable, Sendable {
    public let id: String
    public let guards: [RuntimeAdapterPendingGuard]
}

public struct RuntimeAdapterReport: Encodable, Sendable {
    public let scope = "public-runtime-full-observation"
    public let nativeMappingsRatified = false
    public let status: String
    public let totalRuntimeCases: Int
    public let eligibleIDs: [String]
    /// SHA-256 of exact sorted ASCII IDs, each followed by LF, including the last.
    public let eligibleIDsSHA256: String
    public let runtimePassed: [String]
    public let failed: [ConformanceFailure]
    public let pending: [RuntimeAdapterPendingCase]
}

/// A separate, reproducible inventory of M5 adapter eligibility. Input shape
/// guards and actual callback consultations determine dispositions; no expected
/// field can select a native configuration or change eligibility.
public enum RuntimeAdapterQualification {
    public static func run(referenceDirectory: URL) throws -> RuntimeAdapterReport {
        let corpus = try ConformanceRunner.load(referenceDirectory: referenceDirectory)
        let rows = corpus.cases.filter { ["get", "getResult", "construct"].contains($0.operation) }
        let session = RuntimeObservations.Session()
        var eligible: [String] = [], passed: [String] = []
        var failed: [ConformanceFailure] = [], pending: [RuntimeAdapterPendingCase] = []
        for row in rows {
            do {
                guard let actual = try session.execute(row) else {
                    guard !session.pendingGuards.isEmpty else { throw ConformanceError("Pending runtime case has no input/consultation guard: \(row.id)") }
                    pending.append(.init(id: row.id, guards: session.pendingGuards)); continue
                }
                eligible.append(row.id)
                if let difference = try JSONComparison.firstDifference(expected: row.expected, actual: actual) {
                    failed.append(.init(id: row.id, detail: difference))
                } else { passed.append(row.id) }
            } catch {
                if eligible.last != row.id { eligible.append(row.id) }
                failed.append(.init(id: row.id, detail: String(describing: error)))
            }
        }
        eligible.sort(); passed.sort(); pending.sort { $0.id < $1.id }
        guard eligible.count + pending.count == rows.count, Set(eligible + pending.map(\.id)).count == rows.count else {
            throw ConformanceError("Runtime adapter inventory is overlapping or incomplete")
        }
        let digest = SHA256.hash(data: Data(eligible.map { $0 + "\n" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(status: failed.isEmpty ? "passed" : "failed", totalRuntimeCases: rows.count,
            eligibleIDs: eligible, eligibleIDsSHA256: digest, runtimePassed: passed, failed: failed, pending: pending)
    }
}
