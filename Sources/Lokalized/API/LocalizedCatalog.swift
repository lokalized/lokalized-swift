/// Authored root entries for one locale, retained in declaration order.
/// Duplicate keys and invalid graphs are refused by `DefaultStrings` during
/// construction, after the supplier has returned. This value does not deduplicate.
public struct LocalizedCatalog: Sendable, ExpressibleByDictionaryLiteral, Sequence {
    public typealias Key = ExactString
    public typealias Value = LocalizedString
    package let orderedStrings: [LocalizedString]
    /// Literal/entry labels are retained for deferred key/model consistency checks.
    package let suppliedKeys: [ExactString]?

    public init(strings: [LocalizedString]) { orderedStrings = strings; suppliedKeys = nil }
    public init(entries: [(ExactString, LocalizedString)]) {
        orderedStrings = entries.map(\.1); suppliedKeys = entries.map(\.0)
    }
    public init(dictionaryLiteral elements: (ExactString, LocalizedString)...) { self.init(entries: elements) }
    public var strings: [LocalizedString] { orderedStrings }
    public var count: Int { orderedStrings.count }
    public var isEmpty: Bool { orderedStrings.isEmpty }
    public func makeIterator() -> IndexingIterator<[LocalizedString]> { orderedStrings.makeIterator() }
}
