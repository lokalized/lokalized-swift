/// Authored root entries for one locale, retained in declaration order.
/// Duplicate keys and invalid graphs are refused by `DefaultStrings` during
/// construction, after the supplier has returned. This value does not deduplicate.
public struct LocalizedCatalog: Sendable, ExpressibleByDictionaryLiteral, Sequence {
    /// The exact catalog key type.
    public typealias Key = ExactString
    /// The immutable localized-entry type.
    public typealias Value = LocalizedString
    package let orderedStrings: [LocalizedString]
    /// Literal/entry labels are retained for deferred key/model consistency checks.
    package let suppliedKeys: [ExactString]?

    /// Creates an ordered catalog from localized entries. Duplicate keys remain present until catalog validation rejects them.
    public init(strings: [LocalizedString]) { orderedStrings = strings; suppliedKeys = nil }
    /// Creates an ordered catalog from localized entries. Duplicate keys remain present until catalog validation rejects them.
    public init(entries: [(ExactString, LocalizedString)]) {
        orderedStrings = entries.map(\.1); suppliedKeys = entries.map(\.0)
    }
    /// Creates an ordered catalog from localized entries. Duplicate keys remain present until catalog validation rejects them.
    public init(dictionaryLiteral elements: (ExactString, LocalizedString)...) { self.init(entries: elements) }
    /// The authored root entries in declaration order.
    public var strings: [LocalizedString] { orderedStrings }
    /// The number of authored root entries, including any duplicate keys.
    public var count: Int { orderedStrings.count }
    /// Whether the catalog contains no root entries.
    public var isEmpty: Bool { orderedStrings.isEmpty }
    /// Iterates the stored entries in their documented order.
    public func makeIterator() -> IndexingIterator<[LocalizedString]> { orderedStrings.makeIterator() }
}
