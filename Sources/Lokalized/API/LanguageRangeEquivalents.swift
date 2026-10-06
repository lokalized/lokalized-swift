/// Selects the pinned table used to expand RFC 4647 ranges.
/// Swift's JDK mode is the bundled Corretto 21.0.11 table, not a host JVM.
public enum LanguageRangeEquivalents: String, CaseIterable, Hashable, Sendable {
    /// Expand language ranges using the bundled IANA registry snapshot.
    case ianaRegistry = "IANA_REGISTRY"
    /// Expand language ranges using the bundled Java 21 compatibility table.
    case jdk = "JDK"
}
