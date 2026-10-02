import CryptoKit
import Foundation
import Lokalized

/// Development-only replay inputs. The shared canonical corpus sorts object
/// keys, while the oracle reads JSON.stringify output from authored fixtures.
/// This pinned sidecar restores the input bytes without consulting expectations.
enum MaterializedFixtures {
    static let sha256 = "8203dbeae22b862f7514c3fec2786a42782067f1f532b96aab9314b1d5aea146"

    static func load(referenceDirectory: URL) throws -> [ExactString: [ExactString: Data]] {
        let data = try ConformanceRunner.boundedRead(
            referenceDirectory.appendingPathComponent("materialized-fixtures.json"), maximumBytes: 16_777_216)
        guard digest(data) == sha256 else {
            throw ConformanceError("Materialized fixture digest does not match the compiled baseline")
        }
        let root = try JSONReader.parse(data, limits: ConformanceRunner.corpusLimits).checkedObject(at: "materializedFixtures")
        guard root["formatVersion"].numberLiteral == "1",
              try root.string("corpusSHA256", at: "materializedFixtures") == ConformanceRunner.corpusSHA256 else {
            throw ConformanceError("Materialized fixture format or corpus identity differs")
        }
        let fixtures = try root.value("fixtures", at: "materializedFixtures").checkedObject(at: "materializedFixtures.fixtures")
        var decoded: [ExactString: [ExactString: Data]] = [:]
        for (id, fixture) in fixtures {
            let fields = try fixture.checkedObject(at: "materializedFixtures.fixtures.\(id)")
            let files = try fields.value("files", at: "materializedFixtures.fixture").checkedObject(at: "materializedFixtures.fixture.files")
            var bytesByName: [ExactString: Data] = [:]
            for (name, value) in files {
                let file = try value.checkedObject(at: "materializedFixtures.file", allowed: ["bytesBase64", "byteCount", "sha256"])
                try file.requireKeys(["bytesBase64", "byteCount", "sha256"], at: "materializedFixtures.file")
                guard let bytes = try Data(base64Encoded: file.string("bytesBase64", at: "materializedFixtures.file")),
                      file["byteCount"].numberLiteral == String(bytes.count),
                      try file.string("sha256", at: "materializedFixtures.file") == digest(bytes) else {
                    throw ConformanceError("Materialized fixture bytes disagree with their digest or length: \(id)/\(name)")
                }
                bytesByName[name] = bytes
            }
            decoded[id] = bytesByName
        }
        return decoded
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
    }
}
