/// A decoded manifest value, retaining exact property names and member order.
/// This is a semantic-input carrier; raw bytes use the duplicate-aware parser.
/// Object members have JavaScript object semantics at validation: later exact
/// names replace earlier values without moving their first position.
public indirect enum StringsManifestValue: Sendable {
    case object([StringsManifestMember])
    case array([StringsManifestValue])
    case string(String)
    /// Manifest schema numbers follow binary64 semantics, separately from the
    /// exact decimal values used by catalog expressions and plural operands.
    case number(Double)
    case bool(Bool)
    case null
}

public struct StringsManifestMember: Sendable {
    public let name: ExactString
    public let value: StringsManifestValue
    public init(name: ExactString, value: StringsManifestValue) {
        self.name = name; self.value = value
    }
}

public struct StringsManifestFile: Sendable {
    public let url: String
    public let sha256: String
    public let decodedBytes: Int?
    public init(url: String, sha256: String, decodedBytes: Int? = nil) {
        self.url = url; self.sha256 = sha256; self.decodedBytes = decodedBytes
    }
}

/// An immutable manifest claim. Creating this value is not verification:
/// parsing, validation and every planning door revalidate its contents and
/// recompute its catalog identity before a future loader may perform I/O.
public struct StringsManifestV1: Sendable {
    public let formatVersion: Int
    public let catalogVersion: String
    public let catalogFingerprint: String
    public let cldrVersion: String
    public let dataFingerprint: String
    public let behavioralVectorsVersion: String
    public let localeDataMode: String
    public let cardinalityMode: String
    public let ianaRegistryDate: String
    public let ianaDataFingerprint: String
    public let fallbackLocale: String
    public let baseUrl: String
    public let files: [ExactString: StringsManifestFile]
    public let tiebreakerLocalesByLanguageCode: [ExactString: [String]]

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

public struct ManifestLocaleConfiguration: Sendable {
    public let fallbackLocale: String
    public let supportedLocales: [String]
    public let tiebreakerLocalesByLanguageCode: [String: [String]]
    public init(fallbackLocale: String, supportedLocales: [String], tiebreakerLocalesByLanguageCode: [String: [String]]) {
        self.fallbackLocale = fallbackLocale; self.supportedLocales = supportedLocales
        self.tiebreakerLocalesByLanguageCode = tiebreakerLocalesByLanguageCode
    }
}

/// A manifest-backed file in first-use planning order. The URL is already
/// resolved; a transport must not resolve it a second time.
public struct FetchEntry: Sendable {
    public let locale: String
    public let url: String
    public let sha256: String
    public let expectedDecodedBytes: Int?
    public init(locale: String, url: String, sha256: String, expectedDecodedBytes: Int? = nil) {
        self.locale = locale; self.url = url; self.sha256 = sha256
        self.expectedDecodedBytes = expectedDecodedBytes
    }
}
