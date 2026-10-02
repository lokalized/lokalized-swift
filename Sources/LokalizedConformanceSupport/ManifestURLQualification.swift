import CryptoKit
import Foundation
import Lokalized

public struct ManifestURLPendingCapability: Encodable, Sendable {
    public let id: String
    public let feature: String
}
public struct ManifestURLAuditReport: Encodable, Sendable {
    public let status: String
    public let total: Int
    public let qualified: Int
    public let pendingNativeCapability: Int
    public let failed: Int
    public let runtimePassed: Int
    public let qualifiedIDs: [String]
    public let qualifiedIDSetSHA256: String
    public let pendingNativeCapabilities: [ManifestURLPendingCapability]
    public let archiveSHA256: String
    public let pendingIDSetSHA256: String
    public let failures: [String]
}
public extension ConformanceRunner {
    /// Actual original URL parser observations against a separately pinned Node
    /// URL oracle. Explicit unimplemented host scopes are retained as pending.
    static func manifestURLAudit(referenceDirectory: URL) throws -> ManifestURLAuditReport {
        let bytes = try boundedRead(referenceDirectory.appendingPathComponent("manifest-url-goldens.json"), maximumBytes: 2_097_152)
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard sha == "5aeef3e07d1a1f0464baf4f0748d6902cebe4a61964cb1398419d1eb89ddd6fd" else { throw ConformanceError("Manifest URL archive digest differs") }
        guard let document = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let rows = document["rows"] as? [[String: Any]], rows.count == 3_479,
              document["formatVersion"] as? Int == 1, document["recipeVersion"] as? Int == 1,
              document["nodeVersion"] as? String == "v26.5.0",
              document["nodeBinarySha256"] as? String == "87026f4b570ee090c0e0b48e8c6586ede31952695aac2b0021cc67e44987d511",
              document["recipeSha256"] as? String == "23339e710caf4a7801151bfce5a3a1be5743094d7cab2e7ee7077b928f5887d3" else { throw ConformanceError("Manifest URL archive shape differs") }
        var failures: [String] = [], failed = 0, passed = 0, qualifiedIDs: [String] = [], pending: [ManifestURLPendingCapability] = [], seen: Set<String> = []
        for row in rows {
            guard let id = row["id"] as? String, let input = row["input"] as? [String: String], let reference = input["input"],
                  let expected = row["expected"] as? [String: String] else { throw ConformanceError("Manifest URL row shape differs") }
            guard seen.insert(id).inserted else { throw ConformanceError("Duplicate manifest URL ID") }
            let feature = ManifestURL.unqualifiedFeature(reference: reference, relativeTo: input["base"])
            var pass = false
            if let declared = row["unqualifiedFeature"] as? String {
                pending.append(.init(id: id, feature: declared)); pass = feature?.rawValue == declared
            } else {
                qualifiedIDs.append(id)
                if feature == nil {
                    do { let actual = try ManifestURL.resolve(reference, relativeTo: input["base"]); pass = expected["url"].map { ExactString($0) == ExactString(actual) } ?? false }
                    catch { pass = expected["error"] == "invalid" && (error as? ManifestURL.Failure)?.kind == .invalidURL }
                }
            }
            if pass && row["unqualifiedFeature"] as? String == nil { passed += 1 }
            if !pass { failed += 1; if failures.count < 32 { failures.append(id) } }
        }
        guard qualifiedIDs == qualifiedIDs.sorted(), pending.map(\.id) == pending.map(\.id).sorted(),
              Set(qualifiedIDs).isDisjoint(with: Set(pending.map(\.id))), qualifiedIDs.count + pending.count == rows.count else {
            throw ConformanceError("Manifest URL capability partition differs")
        }
        func idDigest(_ ids: [String]) -> String {
            SHA256.hash(data: Data(ids.map { $0 + "\n" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
        }
        return .init(status: failed == 0 ? "passed" : "failed", total: rows.count, qualified: qualifiedIDs.count, pendingNativeCapability: pending.count,
                     failed: failed, runtimePassed: passed, qualifiedIDs: qualifiedIDs, qualifiedIDSetSHA256: idDigest(qualifiedIDs),
                     pendingNativeCapabilities: pending, archiveSHA256: sha, pendingIDSetSHA256: idDigest(pending.map(\.id)), failures: failures)
    }
}
