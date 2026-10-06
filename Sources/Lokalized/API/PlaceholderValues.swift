/// Immutable raw caller values with exact UTF-16 placeholder-name identity.
/// An absent key differs from a key whose value is `.null`.
public struct PlaceholderValues: Sendable, ExpressibleByDictionaryLiteral, Sequence {
    /// The exact UTF-16 placeholder-name type.
    public typealias Key = ExactString
    /// The typed caller-value type.
    public typealias Value = PlaceholderValue
    /// One placeholder name and its associated value.
    public typealias Element = (key: ExactString, value: PlaceholderValue)
    package let dictionary: [ExactString: PlaceholderValue]

    /// A placeholder collection with no entries.
    public static let empty = Self([:])
    /// Creates caller values keyed by exact placeholder names. No value conversion or display callback runs during construction.
    public init(_ dictionary: [ExactString: PlaceholderValue]) { self.dictionary = dictionary }
    /// Later entries replace earlier values with the same exact name.
    public init(entries: [(ExactString, PlaceholderValue)]) {
        var values: [ExactString: PlaceholderValue] = [:]
        for (key, value) in entries { values[key] = value }
        dictionary = values
    }
    /// Creates caller values keyed by exact placeholder names. No value conversion or display callback runs during construction.
    public init(dictionaryLiteral elements: (ExactString, PlaceholderValue)...) { self.init(entries: elements) }
    /// Returns the value for an exact placeholder name, or `nil` when absent. An explicitly supplied null returns `.null`.
    public subscript(_ key: ExactString) -> PlaceholderValue? { dictionary[key] }
    /// The number of distinct exact placeholder names.
    public var count: Int { dictionary.count }
    /// Whether no placeholder names are present.
    public var isEmpty: Bool { dictionary.isEmpty }
    /// The set of exact placeholder names.
    public var keys: Set<ExactString> { Set(dictionary.keys) }
    /// Iteration is deterministic in exact UTF-16 key order.
    public func makeIterator() -> IndexingIterator<[Element]> {
        dictionary.keys.sorted().map { (key: $0, value: dictionary[$0]!) }.makeIterator()
    }
}
