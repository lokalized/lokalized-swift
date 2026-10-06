/// Library version and bundled locale, plural, and Unicode data identifiers.
/// Use these values to inspect catalog compatibility or record the data version
/// used by a translation runtime.
public struct BuildMetadata: Hashable, Sendable {
    /// The identifier of the library that produced this build.
    public let producerImplementation: String
    /// The library version, such as `1.0.0`.
    public let producerVersion: String
    /// The bundled Unicode CLDR data version.
    public let cldrVersion: String
    /// The SHA-256 fingerprint of the bundled locale and plural data.
    public let dataFingerprint: String
    /// The snapshot date of the bundled IANA language subtag registry.
    public let ianaRegistryDate: String
    /// The SHA-256 fingerprint of the bundled IANA registry data.
    public let ianaDataFingerprint: String
    /// The version of the shared cross-platform compatibility data.
    public let behavioralVectorsVersion: String
    /// The locale data source; this build uses `pinned` data.
    public let localeDataMode: String
    /// The plural arithmetic mode; this build uses `exact` arithmetic.
    public let cardinalityMode: String
    /// The Unicode version used to validate expression identifiers.
    public let identifierUnicodeVersion: String

    /// The version and data identifiers for the running library.
    public static let current = Self(
        producerImplementation: "lokalized-swift",
        producerVersion: "1.0.0",
        cldrVersion: "48.2",
        dataFingerprint: "9b4f24165b6dd1ee6dbb5f0822abc7bcde49c5b94d35903045826b45e1f30e68",
        ianaRegistryDate: "2026-09-17",
        ianaDataFingerprint: "87b3a43b03f490206cead05d865357bd7cfc3953a52ec4d8405243f699385815",
        behavioralVectorsVersion: "1.1.0",
        localeDataMode: "pinned",
        cardinalityMode: "exact",
        identifierUnicodeVersion: "15.0"
    )

    private init(
        producerImplementation: String, producerVersion: String, cldrVersion: String,
        dataFingerprint: String, ianaRegistryDate: String, ianaDataFingerprint: String,
        behavioralVectorsVersion: String, localeDataMode: String, cardinalityMode: String, identifierUnicodeVersion: String
    ) {
        self.producerImplementation = producerImplementation
        self.producerVersion = producerVersion
        self.cldrVersion = cldrVersion
        self.dataFingerprint = dataFingerprint
        self.ianaRegistryDate = ianaRegistryDate
        self.ianaDataFingerprint = ianaDataFingerprint
        self.behavioralVectorsVersion = behavioralVectorsVersion
        self.localeDataMode = localeDataMode
        self.cardinalityMode = cardinalityMode
        self.identifierUnicodeVersion = identifierUnicodeVersion
    }
}
