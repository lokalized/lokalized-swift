/// An immutable, ordered set of representative values and its repetition flag.
///
/// This is the sample container shared with Java's `Range`, rather than a pair
/// of numeric bounds. Use `Lokalized.Range` when Swift's `Range` is also in scope.
public struct Range<Value>: Sequence {
    public let values: [Value]
    public let isInfinite: Bool

    public init(values: [Value], isInfinite: Bool) {
        self.values = values
        self.isInfinite = isInfinite
    }

    public static func ofFiniteValues(_ values: [Value]) -> Self {
        .init(values: values, isInfinite: false)
    }

    public static func ofFiniteValues(_ values: Value...) -> Self { ofFiniteValues(values) }

    public static func ofInfiniteValues(_ values: [Value]) -> Self {
        .init(values: values, isInfinite: true)
    }

    public static func ofInfiniteValues(_ values: Value...) -> Self { ofInfiniteValues(values) }
    public static func emptyFiniteRange() -> Self { ofFiniteValues([]) }
    public static func emptyInfiniteRange() -> Self { ofInfiniteValues([]) }
    public func makeIterator() -> IndexingIterator<[Value]> { values.makeIterator() }
}

extension Range: Equatable where Value: Equatable {}
extension Range: Hashable where Value: Hashable {}
extension Range: Sendable where Value: Sendable {}
