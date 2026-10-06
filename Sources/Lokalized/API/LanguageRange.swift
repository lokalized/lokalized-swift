/// Invalid language-range syntax or preference weight.
/// Inspect `kind` and `message` for the reason parsing or construction failed.
public struct LanguageRangeError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The category of the failure.
    public enum Kind: String, Hashable, Sendable {
        /// An `invalidArgument` means the range or weight is invalid; `indexOutOfBounds` identifies an unusable hyphens-only range.
        case invalidArgument, indexOutOfBounds
    }
    /// The category of the failure.
    public let kind: Kind
    /// The diagnostic explanation of the failure.
    public let message: String
    /// The diagnostic message.
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
    /// The lowercased RFC 4647 extended language range, including any wildcard subtags.
    public let range: String
    /// The preference weight. Positive finite values are eligible for matching; zero excludes a range.
    public let weight: Double
    /// Strict header parsing with pinned equivalence expansion. This applies no
    /// raw header length or matcher range-count cap; callers choose those policies.
    public static func parse(_ ranges: String, equivalents: LanguageRangeEquivalents = .ianaRegistry) throws -> [LanguageRange] {
        try LanguageRangeParser.parse(ranges, equivalents: equivalents)
    }
    private final class NaNIdentity: Sendable {}
    private let nanIdentity: NaNIdentity?

    /// Creates a language preference with a default weight of 1.
    ///
    /// The range must satisfy RFC 4647 extended-range syntax. Weights below 0 or above 1 throw `LanguageRangeError`.
    /// A non-finite weight cannot win a locale match.
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

    /// The range with a `;q=` suffix when its weight differs from 1.
    public var description: String {
        weight == 1 ? range : range + ";q=" + JavaFloatingPoint.render(weight)
    }

    /// Compares the normalized range and weight. Independently constructed NaN weights are distinct; a copied range retains its NaN identity.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.range == rhs.range else { return false }
        if lhs.weight.isNaN && rhs.weight.isNaN { return lhs.nanIdentity === rhs.nanIdentity }
        return lhs.weight == rhs.weight
    }

    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(range)
        // JDK's signed-zero hashes disagree despite equal weights. Swift keeps
        // its Hashable contract; NaN identities may harmlessly share a hash.
        hasher.combine(weight == 0 ? UInt64(0) : weight.isNaN ? 0x7ff8000000000000 : weight.bitPattern)
    }
}
