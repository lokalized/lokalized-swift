import CryptoKit
import Foundation
import Lokalized

public struct DiagnosticTextObservation: Encodable, Sendable {
    public let id: String
    public let door: String
    public let outcome = "threw"
    public let name = "StringsParseError"
    public let message: String
    public let source: String
    public let path: String?

    private enum CodingKeys: String, CodingKey { case id, door, outcome, name, message, source, path }
    public func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id); try box.encode(door, forKey: .door)
        try box.encode(outcome, forKey: .outcome); try box.encode(name, forKey: .name)
        try box.encode(message, forKey: .message); try box.encode(source, forKey: .source)
        if let path { try box.encode(path, forKey: .path) } else { try box.encodeNil(forKey: .path) }
    }
}

public struct DiagnosticTextReport: Encodable, Sendable {
    public let formatVersion = 1
    public let profileID = "diagnostic-text-v1.1"
    public let profileVersion = "1.1.0"
    public let artifactSHA256: String
    public let totalCases: Int
    public let status: String
    public let failed: [ConformanceFailure]
    public let observations: [DiagnosticTextObservation]
}

/// Development-only qualification through actual public parsers, with exact
/// UTF-16 comparison. The expected text is never used to construct an error.
public enum DiagnosticTextQualification {
    public static let artifactSHA256 = "1394c9136089b2b343f562f4ff7ade8d209f7b049b784fe1cc02eb041045c2a2"

    private struct Profile: Decodable {
        let formatVersion: Int
        let profileID: String
        let profileVersion: String
        let cases: [Row]
    }
    private struct Row: Decodable {
        let id: String
        let door: String
        let document: String
        let source: String
        let expected: Expected
    }
    private struct Expected: Decodable {
        let message: String
        let path: String
    }

    public static func run(referenceDirectory: URL) throws -> DiagnosticTextReport {
        let data = try ConformanceRunner.boundedRead(referenceDirectory.appendingPathComponent("diagnostic-text-v1.1.json"), maximumBytes: 1_048_576)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == artifactSHA256 else { throw ConformanceError("Diagnostic text artifact digest differs") }
        let profile = try JSONDecoder().decode(Profile.self, from: data)
        guard profile.formatVersion == 1, profile.profileID == "diagnostic-text-v1.1", profile.profileVersion == "1.1.0",
              profile.cases.count == 36 else { throw ConformanceError("Diagnostic profile inventory differs") }
        var observations: [DiagnosticTextObservation] = [], failures: [ConformanceFailure] = []
        for row in profile.cases {
            do {
                let error: StringsParseError
                do {
                    switch row.door {
                    case "catalog": _ = try LocalizedStringLoader.parse(row.document, locale: "en", source: row.source)
                    case "manifest": _ = try LocalizedStringLoader.parseStringsManifest(row.document, source: row.source)
                    default: throw ConformanceError("Unknown diagnostic parser door")
                    }
                    throw ConformanceError("Duplicate document unexpectedly returned")
                } catch let actual as StringsParseError { error = actual }
                let actual = DiagnosticTextObservation(id: row.id, door: row.door, message: error.message, source: error.source, path: error.path)
                observations.append(actual)
                guard Array(error.message.utf16) == Array(row.expected.message.utf16),
                      Array(error.source.utf16) == Array(row.source.utf16),
                      error.path.map({ Array($0.utf16) }) == (row.door == "catalog" ? Array(row.expected.path.utf16) : nil),
                      error.line == nil, error.column == nil, error.cause == nil else {
                    throw ConformanceError("Actual diagnostic text/envelope differs")
                }
            } catch { failures.append(.init(id: row.id, detail: String(describing: error))) }
        }
        return .init(artifactSHA256: digest, totalCases: profile.cases.count, status: failures.isEmpty ? "passed" : "failed",
                     failed: failures, observations: observations)
    }
}
