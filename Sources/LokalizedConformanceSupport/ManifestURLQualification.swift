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
    public let unicodeDomains: ManifestIDNAAuditReport
}
public struct ManifestIDNAAuditReport: Encodable, Sendable {
    public let status: String
    public let total: Int
    public let failed: Int
    public let runtimePassed: Int
    public let qualifiedIDs: [String]
    public let qualifiedIDSetSHA256: String
    public let archiveSHA256: String
    public let sourceSHA256: String
    public let propertyProfileSHA256: String
    public let propertyDataSourceSHA256: String
    public let propertyDiscriminantRows: Int
    public let normalizationProfileSHA256: String
    public let normalizationDiscriminantRows: Int
    public let oracleRuntimeLockSHA256: String
    public let excludedIllFormedSourceLines: [Int]
    public let failures: [String]
}
public extension ConformanceRunner {
    /// Actual original URL parser observations against a separately pinned Node
    /// URL oracle. Historical feature labels in the frozen archive describe
    /// input coverage; every archived expected outcome is now executed.
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
        var failures: [String] = [], failed = 0, passed = 0, qualifiedIDs: [String] = [], seen: Set<String> = []
        let pending: [ManifestURLPendingCapability] = []
        for row in rows {
            guard let id = row["id"] as? String, let input = row["input"] as? [String: String], let reference = input["input"],
                  let expected = row["expected"] as? [String: String] else { throw ConformanceError("Manifest URL row shape differs") }
            guard seen.insert(id).inserted else { throw ConformanceError("Duplicate manifest URL ID") }
            let feature = ManifestURL.unqualifiedFeature(reference: reference, relativeTo: input["base"])
            var pass = false
            qualifiedIDs.append(id)
            if feature == nil {
                do { let actual = try ManifestURL.resolve(reference, relativeTo: input["base"]); pass = expected["url"].map { ExactString($0) == ExactString(actual) } ?? false }
                catch { pass = expected["error"] == "invalid" && (error as? ManifestURL.Failure)?.kind == .invalidURL }
            }
            if pass { passed += 1 }
            if !pass { failed += 1; if failures.count < 32 { failures.append(id) } }
        }
        guard qualifiedIDs == qualifiedIDs.sorted(), pending.map(\.id) == pending.map(\.id).sorted(),
              Set(qualifiedIDs).isDisjoint(with: Set(pending.map(\.id))), qualifiedIDs.count + pending.count == rows.count else {
            throw ConformanceError("Manifest URL capability partition differs")
        }
        func idDigest(_ ids: [String]) -> String {
            SHA256.hash(data: Data(ids.map { $0 + "\n" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
        }
        let unicodeDomains = try manifestIDNAAudit(referenceDirectory: referenceDirectory)
        return .init(status: failed == 0 && unicodeDomains.status == "passed" ? "passed" : "failed", total: rows.count, qualified: qualifiedIDs.count, pendingNativeCapability: pending.count,
                     failed: failed, runtimePassed: passed, qualifiedIDs: qualifiedIDs, qualifiedIDSetSHA256: idDigest(qualifiedIDs),
                     pendingNativeCapabilities: pending, archiveSHA256: sha, pendingIDSetSHA256: idDigest(pending.map(\.id)), failures: failures, unicodeDomains: unicodeDomains)
    }

    /// URL observations for every scalar-compatible Unicode 17 IdnaTestV2
    /// source, plus explicit browser parsing boundaries. This profile has
    /// relaxed DNS/hyphen/STD3 rules and does not claim strict UTS #46 support.
    static func manifestIDNAAudit(referenceDirectory: URL) throws -> ManifestIDNAAuditReport {
        let bytes = try boundedGzipRead(referenceDirectory.appendingPathComponent("manifest-idna-goldens.json.gz"),
                                        maximumCompressedBytes: 2_097_152, maximumDecodedBytes: 33_554_432)
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard sha == "7f84ecb403b6e772f00dfa851d7de42e6d9556998dbb0b47feca23c8fff380db" else { throw ConformanceError("Manifest IDNA archive digest differs") }
        guard let document = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let rows = document["rows"] as? [[String: Any]], rows.count == 56_513,
              document["formatVersion"] as? Int == 1, document["recipeVersion"] as? Int == 1,
              document["nodeVersions"] as? [String: String] == ["node": "v26.5.0", "unicode": "17.0", "icu": "78.3", "ada": "4.0.0"],
              document["nodeBinarySHA256"] as? String == "87026f4b570ee090c0e0b48e8c6586ede31952695aac2b0021cc67e44987d511",
              document["sourceSHA256"] as? String == "beb5d0be20e896189b03209a82fdc34f06351502bbd4b8e2523583fc2954d9cf",
              document["propertyProfileSHA256"] as? String == "84ae2c73b06823e54716dff80f7f539e588a676e7ff8529424046fe34f7a1098",
              document["propertyDataSourceSHA256"] as? String == "ac8fba37ceddb7c10ca5a24fd57a0f0a0ca32cd3d391e40c6f9f6b7af3801fd4",
              document["normalizationProfileSHA256"] as? String == "9cb7782123a2f08f8a69a8ec702ff7910cff69cd03773e6d665d79ed5a4b327c",
              document["oracleRuntimeLockSHA256"] as? String == "e0fa1af12b31b3750be894db9a892775b672e5d2577923b84e7c83154130cb1d",
              document["excludedIllFormedSourceLines"] as? [Int] == [548, 549],
              document["recipeSHA256"] as? String == "71d26bf09acb9ca75db16f704241a67d491db5d6b4ffcdd8758830e529972aa3" else {
            throw ConformanceError("Manifest IDNA archive provenance differs")
        }
        let runtimeLock = try boundedRead(referenceDirectory.appendingPathComponent("IDNA-Compatibility/oracle-runtime-lock.json"), maximumBytes: 65_536)
        let runtimeLockSHA = SHA256.hash(data: runtimeLock).map { String(format: "%02x", $0) }.joined()
        guard runtimeLockSHA == "e0fa1af12b31b3750be894db9a892775b672e5d2577923b84e7c83154130cb1d" else {
            throw ConformanceError("Manifest IDNA oracle runtime lock digest differs")
        }
        var failures: [String] = [], failed = 0, passed = 0, ids: [String] = [], seen: Set<String> = []
        for row in rows {
            guard let id = row["id"] as? String, let input = row["input"] as? [String: String], let reference = input["input"],
                  let expected = row["expected"] as? [String: String], seen.insert(id).inserted else {
                throw ConformanceError("Manifest IDNA row shape/identity differs")
            }
            ids.append(id)
            var pass: Bool
            do { let actual = try ManifestURL.resolve(reference, relativeTo: input["base"]); pass = expected["url"].map { ExactString($0) == ExactString(actual) } ?? false }
            catch { pass = expected["error"] == "invalid" && (error as? ManifestURL.Failure)?.kind == .invalidURL }
            if pass { passed += 1 } else { failed += 1; if failures.count < 32 { failures.append(id) } }
        }
        let propertyRows = ids.filter { $0.hasPrefix("manifest-idna-property-") }.count
        let normalizationRows = ids.filter { $0.hasPrefix("manifest-idna-normalization-") }.count
        guard ids == ids.sorted(), propertyRows == 32_203, normalizationRows == 17_062 else { throw ConformanceError("Manifest IDNA IDs differ from sorted archive") }
        let idDigest = SHA256.hash(data: Data(ids.map { $0 + "\n" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(status: failed == 0 ? "passed" : "failed", total: rows.count, failed: failed, runtimePassed: passed,
                     qualifiedIDs: ids, qualifiedIDSetSHA256: idDigest, archiveSHA256: sha,
                     sourceSHA256: "beb5d0be20e896189b03209a82fdc34f06351502bbd4b8e2523583fc2954d9cf",
                     propertyProfileSHA256: "84ae2c73b06823e54716dff80f7f539e588a676e7ff8529424046fe34f7a1098",
                     propertyDataSourceSHA256: "ac8fba37ceddb7c10ca5a24fd57a0f0a0ca32cd3d391e40c6f9f6b7af3801fd4",
                     propertyDiscriminantRows: propertyRows,
                     normalizationProfileSHA256: "9cb7782123a2f08f8a69a8ec702ff7910cff69cd03773e6d665d79ed5a4b327c",
                     normalizationDiscriminantRows: normalizationRows, oracleRuntimeLockSHA256: runtimeLockSHA,
                     excludedIllFormedSourceLines: [548, 549], failures: failures)
    }
}
