/// An immutable, ordered set of representative values and its repetition flag.
///
/// Plural sample APIs return recorded values here; `isInfinite` indicates that
/// additional values belong to the category. Use `Lokalized.Range` to distinguish
/// this sample container from Swift's numeric interval type.
public struct Range<Value>: Sequence {
    /// The representative sample values, in their supplied order.
    public let values: [Value]
    /// Whether the category has further values beyond the recorded samples. Iteration visits only `values`.
    public let isInfinite: Bool

    /// Creates representative samples in the supplied order and records whether more values exist beyond those samples.
    public init(values: [Value], isInfinite: Bool) {
        self.values = values
        self.isInfinite = isInfinite
    }

    /// Creates finite representative samples from the supplied values, preserving their order.
    public static func ofFiniteValues(_ values: [Value]) -> Self {
        .init(values: values, isInfinite: false)
    }

    /// Creates finite representative samples from the supplied values, preserving their order.
    public static func ofFiniteValues(_ values: Value...) -> Self { ofFiniteValues(values) }

    /// Creates representative samples for a category with additional values beyond those recorded. Iteration still visits only the supplied samples.
    public static func ofInfiniteValues(_ values: [Value]) -> Self {
        .init(values: values, isInfinite: true)
    }

    /// Creates representative samples for a category with additional values beyond those recorded. Iteration still visits only the supplied samples.
    public static func ofInfiniteValues(_ values: Value...) -> Self { ofInfiniteValues(values) }
    /// Creates a finite sample collection with no values.
    public static func emptyFiniteRange() -> Self { ofFiniteValues([]) }
    /// Creates an empty recorded sample collection marked as having additional values.
    public static func emptyInfiniteRange() -> Self { ofInfiniteValues([]) }
    /// Iterates the stored entries in their documented order.
    public func makeIterator() -> IndexingIterator<[Value]> { values.makeIterator() }
}

extension Range: Equatable where Value: Equatable {}
extension Range: Hashable where Value: Hashable {}
extension Range: Sendable where Value: Sendable {}
