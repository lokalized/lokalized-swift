import Foundation

/// The translation identity, independent of resource locations and body sizes.
/// A claimed identity is not evidence of an authenticated or verified load.
public struct CatalogIdentity: Hashable, Sendable {
    /// The application-assigned catalog release identifier.
    public let catalogVersion: String
    /// The SHA-256 fingerprint of the catalog identity projection.
    public let catalogFingerprint: String
    /// Creates a catalog identity claim. This does not verify catalog content or authenticate its publisher.
    public init(catalogVersion: String, catalogFingerprint: String) {
        self.catalogVersion = catalogVersion; self.catalogFingerprint = catalogFingerprint
    }
    /// Compares the stored values for equality, preserving exact catalog-text spelling where applicable.
    public static func == (left: Self, right: Self) -> Bool {
        ExactString(left.catalogVersion) == ExactString(right.catalogVersion)
            && ExactString(left.catalogFingerprint) == ExactString(right.catalogFingerprint)
    }
    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ExactString(catalogVersion)); hasher.combine(ExactString(catalogFingerprint))
    }
}

/// The fields included in a catalog's canonical identity fingerprint.
/// Resource URLs, body sizes, and runtime data identifiers are not included.
/// Exact property names are accepted here; manifest validation checks locale tags.
public struct CatalogIdentityInputV1: Sendable {
    /// The manifest identity format version; currently 1.
    public let formatVersion: Int
    /// The application-assigned catalog release identifier.
    public let catalogVersion: String
    /// The fallback locale tag included in the identity projection.
    public let resolvedFallbackLocale: String
    /// Exact locale property names mapped to catalog content digests.
    public let localeToSha256: [ExactString: String]
    /// Exact language property names mapped to ordered locale preferences.
    public let tiebreakerLocalesByLanguageCode: [ExactString: [String]]
    /// Creates the fields used to compute a catalog identity. Locale-name validation is performed separately by manifest validation.
    public init(formatVersion: Int = 1, catalogVersion: String, resolvedFallbackLocale: String,
                localeToSha256: [ExactString: String] = [:],
                tiebreakerLocalesByLanguageCode: [ExactString: [String]] = [:]) {
        self.formatVersion = formatVersion; self.catalogVersion = catalogVersion
        self.resolvedFallbackLocale = resolvedFallbackLocale; self.localeToSha256 = localeToSha256
        self.tiebreakerLocalesByLanguageCode = tiebreakerLocalesByLanguageCode
    }
}
