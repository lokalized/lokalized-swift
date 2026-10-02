import CryptoKit
import Foundation

public extension LocalizedStringLoader {
    /// SHA-256 of the pinned JCS projection; synchronous and independent of URLs.
    static func computeCatalogIdentity(_ input: CatalogIdentityInputV1) throws -> CatalogIdentity {
        let bytes = try catalogIdentityBytes(input)
        return .init(catalogVersion: input.catalogVersion, catalogFingerprint: CatalogIdentityCanonicalizer.digest(bytes))
    }

    /// Projects a manifest claim into identity input, without validating it or
    /// verifying file content. Transport and runtime data fields are excluded.
    static func catalogIdentityInputFor(_ manifest: StringsManifestV1) -> CatalogIdentityInputV1 {
        var fallback = manifest.fallbackLocale
        do {
            let configured = try ManifestLocale.normalizeTag(manifest.fallbackLocale)
            let supported = try manifest.files.keys.sorted().map { try ManifestLocale.normalizeTag($0.string) }
            fallback = ManifestLocale.electFallbackLocale(configured, supported: supported,
                tiebreakerLocalesByLanguageCode: manifest.tiebreakerLocalesByLanguageCode.keys.sorted().reduce(into: [String: [String]]()) {
                    $0[$1.string] = manifest.tiebreakerLocalesByLanguageCode[$1]
                }) ?? configured
        } catch {
            // Like the pinned JS helper, keep identity projection available for
            // intentionally invalid claims; semantic validation owns tag errors.
        }
        return .init(formatVersion: 1, catalogVersion: manifest.catalogVersion,
            resolvedFallbackLocale: fallback, localeToSha256: manifest.files.mapValues(\.sha256),
            tiebreakerLocalesByLanguageCode: manifest.tiebreakerLocalesByLanguageCode)
    }

    /// Exact canonical UTF-8 bytes, without BOM or trailing newline. This
    /// intentionally exposes the narrow identity projection, not a general JCS
    /// serializer for arbitrary floating-point JSON values.
    static func catalogIdentityBytes(_ input: CatalogIdentityInputV1) throws -> Data {
        guard input.formatVersion == 1 else {
            throw ConfigurationError(kind: .invalidArgument,
                message: "A catalog identity input must declare formatVersion 1; received \(input.formatVersion)")
        }
        guard !input.catalogVersion.isEmpty else {
            throw ConfigurationError(kind: .invalidArgument, message: "A catalog identity input must carry a non-empty catalogVersion")
        }
        guard !input.resolvedFallbackLocale.isEmpty else {
            throw ConfigurationError(kind: .invalidArgument, message: "A catalog identity input must carry a non-empty resolvedFallbackLocale")
        }
        var digests: [(ExactString, String)] = []
        for tag in input.localeToSha256.keys.sorted() {
            let digest = input.localeToSha256[tag]!
            guard CatalogIdentityCanonicalizer.isDigest(digest) else {
                throw ConfigurationError(kind: .invalidArgument,
                    message: "The digest for '\(tag.string)' must be a full lowercase hexadecimal SHA-256; received \(CatalogIdentityCanonicalizer.quote(digest))")
            }
            digests.append((tag, CatalogIdentityCanonicalizer.quote(digest)))
        }
        let ties = input.tiebreakerLocalesByLanguageCode.map { code, locales in
            (code, "[" + locales.map(CatalogIdentityCanonicalizer.quote).joined(separator: ",") + "]")
        }
        let projection = CatalogIdentityCanonicalizer.object([
            ("formatVersion", "1"), ("catalogVersion", CatalogIdentityCanonicalizer.quote(input.catalogVersion)),
            ("resolvedFallbackLocale", CatalogIdentityCanonicalizer.quote(input.resolvedFallbackLocale)),
            ("localeToSha256", CatalogIdentityCanonicalizer.object(digests)),
            ("tiebreakerLocalesByLanguageCode", CatalogIdentityCanonicalizer.object(ties))
        ])
        return Data(projection.utf8)
    }
}

package func catalogIdentityInputFor(_ manifest: StringsManifestV1) -> CatalogIdentityInputV1 {
    LocalizedStringLoader.catalogIdentityInputFor(manifest)
}

package enum CatalogIdentityCanonicalizer {
    package static func isDigest(_ value: String) -> Bool {
        let bytes = value.utf8
        return bytes.count == 64 && bytes.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    package static func digest(_ bytes: Data) -> String {
        let hexadecimal: [UInt8] = Array("0123456789abcdef".utf8)
        return String(decoding: SHA256.hash(data: bytes).flatMap { [hexadecimal[Int($0 >> 4)], hexadecimal[Int($0 & 15)]] }, as: UTF8.self)
    }
    package static func object(_ fields: [(ExactString, String)]) -> String {
        "{" + fields.sorted { $0.0 < $1.0 }.map { quote($0.0.string) + ":" + $0.1 }.joined(separator: ",") + "}"
    }
    package static func quote(_ text: String) -> String {
        var result = "\""
        let hexadecimal: [UInt8] = Array("0123456789abcdef".utf8)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 8: result += "\\b"
            case 9: result += "\\t"
            case 10: result += "\\n"
            case 12: result += "\\f"
            case 13: result += "\\r"
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 0...31:
                result += "\\u00"
                result.unicodeScalars.append(UnicodeScalar(hexadecimal[Int(scalar.value >> 4)]))
                result.unicodeScalars.append(UnicodeScalar(hexadecimal[Int(scalar.value & 15)]))
            default: result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }
}
