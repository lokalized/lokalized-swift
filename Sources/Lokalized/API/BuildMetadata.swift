/// The immutable data baseline pinned by this build.
///
/// During development these values identify the intended compatibility baseline;
/// they do not assert that the implementation passes the entire shared corpus.
/// Run the development conformance executable for implementation coverage.
public struct BuildMetadata: Hashable, Sendable {
    public let producerImplementation: String
    public let producerVersion: String
    public let cldrVersion: String
    public let dataFingerprint: String
    public let ianaRegistryDate: String
    public let ianaDataFingerprint: String
    public let behavioralVectorsVersion: String
    public let localeDataMode: String
    public let cardinalityMode: String
    public let identifierUnicodeVersion: String

    public static let current = Self(
        producerImplementation: "lokalized-swift",
        producerVersion: "0.1.0-dev",
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
