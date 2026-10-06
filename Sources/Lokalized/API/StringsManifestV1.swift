/// A decoded JSON value for programmatic manifest validation.
/// Object members preserve exact property names and their order. Validation uses
/// the last value for a repeated name; source parsing rejects duplicate members.
public indirect enum StringsManifestValue: Sendable {
    /// An ordered list of exact-name object members. Validation applies last-value-wins semantics to repeated names.
    case object([StringsManifestMember])
    /// An ordered array of manifest values.
    case array([StringsManifestValue])
    /// A manifest string value.
    case string(String)
    /// Manifest schema numbers follow binary64 semantics, separately from the
    /// exact decimal values used by catalog expressions and plural operands.
    case number(Double)
    /// A manifest Boolean value.
    case bool(Bool)
    /// A manifest null value.
    case null
}

/// One exact-name object member in a decoded manifest, preserving input order.
public struct StringsManifestMember: Sendable {
    /// The exact object property name, preserving its Unicode spelling.
    public let name: ExactString
    /// The decoded value associated with the property.
    public let value: StringsManifestValue
    /// Creates an exact-name decoded object member.
    public init(name: ExactString, value: StringsManifestValue) {
        self.name = name; self.value = value
    }
}

/// A manifest's claimed URL, SHA-256 digest, and optional decoded byte count.
/// Constructing this value does not load a file or verify its contents.
public struct StringsManifestFile: Sendable {
    /// The claimed catalog URL, resolved against the manifest base URL during validation.
    public let url: String
    /// The expected SHA-256 digest of the catalog content.
    public let sha256: String
    /// The optional expected byte count of the decoded catalog content.
    public let decodedBytes: Int?
    /// Creates a catalog file claim. URL, digest, and size validation occurs when the manifest is validated.
    public init(url: String, sha256: String, decodedBytes: Int? = nil) {
        self.url = url; self.sha256 = sha256; self.decodedBytes = decodedBytes
    }
}

/// Catalog locations, content digests, locale settings, and data compatibility
/// requirements for one catalog release.
///
/// Use the parsing or validation helpers to check the manifest and recompute its
/// catalog identity. Planning helpers revalidate the manifest and return catalog
/// requirements without loading local files or making network requests.
public struct StringsManifestV1: Sendable {
    /// The manifest format version; currently 1.
    public let formatVersion: Int
    /// The application-assigned catalog release identifier.
    public let catalogVersion: String
    /// The claimed SHA-256 catalog identity fingerprint, recomputed during validation.
    public let catalogFingerprint: String
    /// The required CLDR data version.
    public let cldrVersion: String
    /// The required locale and plural data fingerprint.
    public let dataFingerprint: String
    /// The required shared compatibility-data version.
    public let behavioralVectorsVersion: String
    /// The required locale data source mode; `pinned`.
    public let localeDataMode: String
    /// The required plural arithmetic mode; `exact`.
    public let cardinalityMode: String
    /// The required IANA registry snapshot date.
    public let ianaRegistryDate: String
    /// The required IANA registry data fingerprint.
    public let ianaDataFingerprint: String
    /// The claimed final fallback locale tag.
    public let fallbackLocale: String
    /// The base URL used to resolve relative catalog locations. This value does not initiate a network request.
    public let baseUrl: String
    /// Exact locale property names mapped to catalog file claims.
    public let files: [ExactString: StringsManifestFile]
    /// Exact language property names mapped to ordered catalog locale preferences.
    public let tiebreakerLocalesByLanguageCode: [ExactString: [String]]

    /// Creates a manifest claim using this build's data identifiers by default.
    ///
    /// Call `LocalizedStringLoader.validateStringsManifest` to validate the claim and recompute its identity.
    /// Construction performs no file or network loading.
    public init(
        formatVersion: Int = 1, catalogVersion: String, catalogFingerprint: String,
        cldrVersion: String = BuildMetadata.current.cldrVersion,
        dataFingerprint: String = BuildMetadata.current.dataFingerprint,
        behavioralVectorsVersion: String = BuildMetadata.current.behavioralVectorsVersion,
        localeDataMode: String = "pinned", cardinalityMode: String = "exact",
        ianaRegistryDate: String = BuildMetadata.current.ianaRegistryDate,
        ianaDataFingerprint: String = BuildMetadata.current.ianaDataFingerprint,
        fallbackLocale: String, baseUrl: String,
        files: [ExactString: StringsManifestFile],
        tiebreakerLocalesByLanguageCode: [ExactString: [String]] = [:]
    ) {
        self.formatVersion = formatVersion; self.catalogVersion = catalogVersion
        self.catalogFingerprint = catalogFingerprint; self.cldrVersion = cldrVersion
        self.dataFingerprint = dataFingerprint; self.behavioralVectorsVersion = behavioralVectorsVersion
        self.localeDataMode = localeDataMode; self.cardinalityMode = cardinalityMode
        self.ianaRegistryDate = ianaRegistryDate; self.ianaDataFingerprint = ianaDataFingerprint
        self.fallbackLocale = fallbackLocale; self.baseUrl = baseUrl
        self.files = files; self.tiebreakerLocalesByLanguageCode = tiebreakerLocalesByLanguageCode
    }

    package var decodedValue: StringsManifestValue {
        func member(_ name: ExactString, _ value: StringsManifestValue) -> StringsManifestMember {
            .init(name: name, value: value)
        }
        let entries = files.keys.sorted().map { tag in
            let file = files[tag]!
            var fields = [member("url", .string(file.url)), member("sha256", .string(file.sha256))]
            if let count = file.decodedBytes { fields.append(member("decodedBytes", .number(Double(count)))) }
            return member(tag, .object(fields))
        }
        let ties = tiebreakerLocalesByLanguageCode.keys.sorted().map { code in
            member(code, .array(tiebreakerLocalesByLanguageCode[code]!.map(StringsManifestValue.string)))
        }
        return .object([
            member("formatVersion", .number(Double(formatVersion))), member("catalogVersion", .string(catalogVersion)),
            member("catalogFingerprint", .string(catalogFingerprint)), member("cldrVersion", .string(cldrVersion)),
            member("dataFingerprint", .string(dataFingerprint)), member("behavioralVectorsVersion", .string(behavioralVectorsVersion)),
            member("localeDataMode", .string(localeDataMode)), member("cardinalityMode", .string(cardinalityMode)),
            member("ianaRegistryDate", .string(ianaRegistryDate)), member("ianaDataFingerprint", .string(ianaDataFingerprint)),
            member("fallbackLocale", .string(fallbackLocale)), member("baseUrl", .string(baseUrl)),
            member("files", .object(entries)), member("tiebreakerLocalesByLanguageCode", .object(ties))
        ])
    }
}

/// Locale selection settings derived from a validated manifest.
public struct ManifestLocaleConfiguration: Sendable {
    /// The normalized final fallback locale.
    public let fallbackLocale: String
    /// The normalized catalog locale tags in deterministic order.
    public let supportedLocales: [String]
    /// Normalized language keys mapped to ordered locale preferences.
    public let tiebreakerLocalesByLanguageCode: [String: [String]]
    /// Creates locale settings for a manifest-derived catalog set.
    public init(fallbackLocale: String, supportedLocales: [String], tiebreakerLocalesByLanguageCode: [String: [String]]) {
        self.fallbackLocale = fallbackLocale; self.supportedLocales = supportedLocales
        self.tiebreakerLocalesByLanguageCode = tiebreakerLocalesByLanguageCode
    }
}

/// A manifest-backed file in first-use planning order. The URL is already
/// resolved. This planning value does not initiate catalog I/O.
public struct FetchEntry: Sendable {
    /// The catalog locale required by the plan.
    public let locale: String
    /// The resolved catalog URL. Lokalized's Swift planning helpers perform no network loading.
    public let url: String
    /// The expected catalog content digest.
    public let sha256: String
    /// The optional expected decoded catalog byte count.
    public let expectedDecodedBytes: Int?
    /// Creates a resolved catalog delivery requirement. No resource is loaded by this initializer.
    public init(locale: String, url: String, sha256: String, expectedDecodedBytes: Int? = nil) {
        self.locale = locale; self.url = url; self.sha256 = sha256
        self.expectedDecodedBytes = expectedDecodedBytes
    }
}
