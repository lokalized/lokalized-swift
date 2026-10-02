/// Immutable raw caller values with exact UTF-16 placeholder-name identity.
/// An absent key differs from a key whose value is `.null`.
public struct PlaceholderValues: Sendable, ExpressibleByDictionaryLiteral, Sequence {
    public typealias Key = ExactString
    public typealias Value = PlaceholderValue
    public typealias Element = (key: ExactString, value: PlaceholderValue)
    package let dictionary: [ExactString: PlaceholderValue]

    public static let empty = Self([:])
    public init(_ dictionary: [ExactString: PlaceholderValue]) { self.dictionary = dictionary }
    /// Later entries replace earlier values with the same exact name.
    public init(entries: [(ExactString, PlaceholderValue)]) {
        var values: [ExactString: PlaceholderValue] = [:]
        for (key, value) in entries { values[key] = value }
        dictionary = values
    }
    public init(dictionaryLiteral elements: (ExactString, PlaceholderValue)...) { self.init(entries: elements) }
    public subscript(_ key: ExactString) -> PlaceholderValue? { dictionary[key] }
    public var count: Int { dictionary.count }
    public var isEmpty: Bool { dictionary.isEmpty }
    public var keys: Set<ExactString> { Set(dictionary.keys) }
    /// Iteration is deterministic in exact UTF-16 key order.
    public func makeIterator() -> IndexingIterator<[Element]> {
        dictionary.keys.sorted().map { (key: $0, value: dictionary[$0]!) }.makeIterator()
    }
}
