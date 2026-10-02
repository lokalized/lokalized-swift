/// Java 21 language-range validation failed. Messages retain the portable Java
/// diagnostic; hyphens-only input has its distinct JDK 21 bounds-error kind.
public struct LanguageRangeError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Hashable, Sendable { case invalidArgument, indexOutOfBounds }
    public let kind: Kind
    public let message: String
    public var description: String { message }
    package init(_ message: String) { self.init(.invalidArgument, message) }
    package init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
}

/// An immutable, lowercased RFC 4647 extended range and its quality weight.
/// Constructing a range expands no equivalents; parsing a header does.
public struct LanguageRange: Hashable, Sendable, CustomStringConvertible {
    public let range: String
    public let weight: Double
    /// Strict header parsing with pinned equivalence expansion. This applies no
    /// raw header length or matcher range-count cap; callers choose those policies.
    public static func parse(_ ranges: String, equivalents: LanguageRangeEquivalents = .ianaRegistry) throws -> [LanguageRange] {
        try LanguageRangeParser.parse(ranges, equivalents: equivalents)
    }
    private final class NaNIdentity: Sendable {}
    private let nanIdentity: NaNIdentity?

    public init(_ range: String, weight: Double = 1) throws {
        guard !(weight < 0 || weight > 1) else {
            throw LanguageRangeError("weight=" + JavaFloatingPoint.render(weight))
        }
        let normalized = LanguageRangeLowercase.apply(range)
        try LanguageRangeParser.validateGrammar(normalized)
        self.range = normalized
        self.weight = weight
        self.nanIdentity = weight.isNaN ? NaNIdentity() : nil
    }

    public var description: String {
        weight == 1 ? range : range + ";q=" + JavaFloatingPoint.render(weight)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.range == rhs.range else { return false }
        if lhs.weight.isNaN && rhs.weight.isNaN { return lhs.nanIdentity === rhs.nanIdentity }
        return lhs.weight == rhs.weight
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(range)
        // JDK's signed-zero hashes disagree despite equal weights. Swift keeps
        // its Hashable contract; NaN identities may harmlessly share a hash.
        hasher.combine(weight == 0 ? UInt64(0) : weight.isNaN ? 0x7ff8000000000000 : weight.bitPattern)
    }
}
