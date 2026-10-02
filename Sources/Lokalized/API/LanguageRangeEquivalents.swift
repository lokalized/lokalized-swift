/// Selects the pinned table used to expand RFC 4647 ranges.
/// Swift's JDK mode is the bundled Corretto 21.0.11 table, not a host JVM.
public enum LanguageRangeEquivalents: String, CaseIterable, Hashable, Sendable {
    case ianaRegistry = "IANA_REGISTRY"
    case jdk = "JDK"
}
