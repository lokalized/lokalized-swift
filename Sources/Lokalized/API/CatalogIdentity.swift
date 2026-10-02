import Foundation

/// The translation identity, independent of resource locations and body sizes.
/// A claimed identity is not evidence of an authenticated or verified load.
public struct CatalogIdentity: Hashable, Sendable {
    public let catalogVersion: String
    public let catalogFingerprint: String
    public init(catalogVersion: String, catalogFingerprint: String) {
        self.catalogVersion = catalogVersion; self.catalogFingerprint = catalogFingerprint
    }
    public static func == (left: Self, right: Self) -> Bool {
        ExactString(left.catalogVersion) == ExactString(right.catalogVersion)
            && ExactString(left.catalogFingerprint) == ExactString(right.catalogFingerprint)
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ExactString(catalogVersion)); hasher.combine(ExactString(catalogFingerprint))
    }
}

/// Exactly the fingerprint projection. The standalone identity API deliberately
/// accepts arbitrary exact property names; manifest tag validation is separate.
public struct CatalogIdentityInputV1: Sendable {
    public let formatVersion: Int
    public let catalogVersion: String
    public let resolvedFallbackLocale: String
    public let localeToSha256: [ExactString: String]
    public let tiebreakerLocalesByLanguageCode: [ExactString: [String]]
    public init(formatVersion: Int = 1, catalogVersion: String, resolvedFallbackLocale: String,
                localeToSha256: [ExactString: String] = [:],
                tiebreakerLocalesByLanguageCode: [ExactString: [String]] = [:]) {
        self.formatVersion = formatVersion; self.catalogVersion = catalogVersion
        self.resolvedFallbackLocale = resolvedFallbackLocale; self.localeToSha256 = localeToSha256
        self.tiebreakerLocalesByLanguageCode = tiebreakerLocalesByLanguageCode
    }
}
