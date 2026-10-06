/// A string whose identity and order use its exact UTF-16 code units.
///
/// Swift's `String` equality treats canonically equivalent Unicode spellings as
/// equal. Lokalized keys, expressions, and source strings retain their spelling,
/// matching Java and JavaScript, so composed and decomposed strings can remain
/// distinct keys. Ordering is lexicographic UTF-16 order, as in Java.
///
/// Inputs are valid Swift strings. This type does not decode or repair malformed
/// UTF-16; file readers must reject unpaired surrogates before creating a string.
public struct ExactString: Hashable, Comparable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    /// The original string, without Unicode normalization.
    public let string: String

    private let codeUnits: [UInt16]

    /// Preserves the supplied string's exact UTF-16 spelling without Unicode normalization.
    public init(_ string: String) {
        self.string = string
        self.codeUnits = Array(string.utf16)
    }

    /// Preserves the supplied string's exact UTF-16 spelling without Unicode normalization.
    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// The length measured in UTF-16 code units, including both halves of a pair.
    public var utf16Count: Int { codeUnits.count }

    /// The human-readable representation of this value.
    public var description: String { string }

    /// Compares exact UTF-16 code units without Unicode normalization.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.codeUnits == rhs.codeUnits
    }

    /// Compares strings lexicographically by their exact UTF-16 code units.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.codeUnits.lexicographicallyPrecedes(rhs.codeUnits)
    }

    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(codeUnits.count)
        for codeUnit in codeUnits {
            hasher.combine(codeUnit)
        }
    }
}
