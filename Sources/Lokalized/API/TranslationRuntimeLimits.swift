/// Immutable safety limits for translation construction and evaluation.
///
/// Character limits count UTF-16 code units. Each locale attempt has one
/// cumulative expansion budget shared by language-form and expression fragments.
/// Omitted initializer arguments use the documented defaults; custom values
/// must remain within each setting's allowed range.
public struct TranslationRuntimeLimits: Hashable, Sendable {
    /// The default maximum decimal coefficient digits: 1,024.
    public static let defaultMaximumNumberPrecision = 1_024
    /// The default maximum absolute decimal scale: 1,024.
    public static let defaultMaximumAbsoluteNumberScale = 1_024
    /// The default maximum explicit visible fractional digits: 1,024.
    public static let defaultMaximumVisibleDecimalPlaces = 1_024
    /// The default maximum compact-decimal exponent: 64.
    public static let defaultMaximumCompactExponent = 64
    /// The default maximum UTF-16 code units in one expression: 2,048.
    public static let defaultMaximumExpressionCharacters = 2_048
    /// The default maximum tokens in one expression: 256.
    public static let defaultMaximumExpressionTokens = 256
    /// The default maximum nested expression groups: 32.
    public static let defaultMaximumExpressionNestingDepth = 32
    /// The default maximum nested generated-placeholder definitions: 32.
    public static let defaultMaximumGeneratedPlaceholderDepth = 32
    /// The default maximum UTF-16 code units in one output or phonetic input: 262,144.
    public static let defaultMaximumInterpolatedOutputCharacters = 262_144
    /// The default maximum cumulative UTF-16 expansion units per locale attempt: 1,048,576.
    public static let defaultMaximumGeneratedExpansionCharacters = 1_048_576

    /// The largest configurable maximum decimal coefficient digits: 4,096.
    public static let hardMaximumNumberPrecision = 4_096
    /// The largest configurable maximum absolute decimal scale: 4,096.
    public static let hardMaximumAbsoluteNumberScale = 4_096
    /// The largest configurable maximum explicit visible fractional digits: 4,096.
    public static let hardMaximumVisibleDecimalPlaces = 4_096
    /// The largest configurable maximum compact-decimal exponent: 4,096.
    public static let hardMaximumCompactExponent = 4_096
    /// The largest configurable maximum UTF-16 code units in one expression: 4,096.
    public static let hardMaximumExpressionCharacters = 4_096
    /// The largest configurable maximum tokens in one expression: 512.
    public static let hardMaximumExpressionTokens = 512
    /// The largest configurable maximum nested expression groups: 64.
    public static let hardMaximumExpressionNestingDepth = 64
    /// The largest configurable maximum nested generated-placeholder definitions: 64.
    public static let hardMaximumGeneratedPlaceholderDepth = 64
    /// The largest configurable maximum UTF-16 code units in one output or phonetic input: 1,048,576.
    public static let hardMaximumInterpolatedOutputCharacters = 1_048_576
    /// The largest configurable maximum cumulative UTF-16 expansion units per locale attempt: 8,388,608.
    public static let hardMaximumGeneratedExpansionCharacters = 8_388_608

    /// The default bounds for translation construction and evaluation.
    public static let defaults = Self()

    /// Maximum decimal precision; allowed range: 1 through 4,096.
    public let maximumNumberPrecision: Int
    /// Maximum absolute decimal scale; allowed range: 0 through 4,096.
    public let maximumAbsoluteNumberScale: Int
    /// Maximum explicitly visible decimal places; allowed range: 0 through 4,096.
    public let maximumVisibleDecimalPlaces: Int
    /// Maximum compact exponent; allowed range: 0 through 4,096.
    public let maximumCompactExponent: Int
    /// Maximum source length of one expression; allowed range: 1 through 4,096.
    public let maximumExpressionCharacters: Int
    /// Maximum token count of one expression; allowed range: 1 through 512.
    public let maximumExpressionTokens: Int
    /// Maximum nested expression groups; allowed range: 0 through 64.
    public let maximumExpressionNestingDepth: Int
    /// Maximum generated-placeholder nesting depth; allowed range: 0 through 64.
    public let maximumGeneratedPlaceholderDepth: Int
    /// Maximum length of one output or phonetic input; allowed range: 1 through 1,048,576.
    public let maximumInterpolatedOutputCharacters: Int
    /// Maximum cumulative expansion length; allowed range: 0 through 8,388,608.
    public let maximumGeneratedExpansionCharacters: Int

    /// Creates the library-default limits.
    public init() {
        maximumNumberPrecision = Self.defaultMaximumNumberPrecision
        maximumAbsoluteNumberScale = Self.defaultMaximumAbsoluteNumberScale
        maximumVisibleDecimalPlaces = Self.defaultMaximumVisibleDecimalPlaces
        maximumCompactExponent = Self.defaultMaximumCompactExponent
        maximumExpressionCharacters = Self.defaultMaximumExpressionCharacters
        maximumExpressionTokens = Self.defaultMaximumExpressionTokens
        maximumExpressionNestingDepth = Self.defaultMaximumExpressionNestingDepth
        maximumGeneratedPlaceholderDepth = Self.defaultMaximumGeneratedPlaceholderDepth
        maximumInterpolatedOutputCharacters = Self.defaultMaximumInterpolatedOutputCharacters
        maximumGeneratedExpansionCharacters = Self.defaultMaximumGeneratedExpansionCharacters
    }

    /// Creates customized limits, throwing if any value is outside its allowed range.
    ///
    /// Omitted arguments use their library defaults. Invalid values are rejected,
    /// without clamping or silently restoring a default.
    public init(
        maximumNumberPrecision: Int = Self.defaultMaximumNumberPrecision,
        maximumAbsoluteNumberScale: Int = Self.defaultMaximumAbsoluteNumberScale,
        maximumVisibleDecimalPlaces: Int = Self.defaultMaximumVisibleDecimalPlaces,
        maximumCompactExponent: Int = Self.defaultMaximumCompactExponent,
        maximumExpressionCharacters: Int = Self.defaultMaximumExpressionCharacters,
        maximumExpressionTokens: Int = Self.defaultMaximumExpressionTokens,
        maximumExpressionNestingDepth: Int = Self.defaultMaximumExpressionNestingDepth,
        maximumGeneratedPlaceholderDepth: Int = Self.defaultMaximumGeneratedPlaceholderDepth,
        maximumInterpolatedOutputCharacters: Int = Self.defaultMaximumInterpolatedOutputCharacters,
        maximumGeneratedExpansionCharacters: Int = Self.defaultMaximumGeneratedExpansionCharacters
    ) throws {
        try Self.validate("maximumNumberPrecision", maximumNumberPrecision, minimum: 1,
                          ceiling: Self.hardMaximumNumberPrecision)
        try Self.validate("maximumAbsoluteNumberScale", maximumAbsoluteNumberScale, minimum: 0,
                          ceiling: Self.hardMaximumAbsoluteNumberScale)
        try Self.validate("maximumVisibleDecimalPlaces", maximumVisibleDecimalPlaces, minimum: 0,
                          ceiling: Self.hardMaximumVisibleDecimalPlaces)
        try Self.validate("maximumCompactExponent", maximumCompactExponent, minimum: 0,
                          ceiling: Self.hardMaximumCompactExponent)
        try Self.validate("maximumExpressionCharacters", maximumExpressionCharacters, minimum: 1,
                          ceiling: Self.hardMaximumExpressionCharacters)
        try Self.validate("maximumExpressionTokens", maximumExpressionTokens, minimum: 1,
                          ceiling: Self.hardMaximumExpressionTokens)
        try Self.validate("maximumExpressionNestingDepth", maximumExpressionNestingDepth, minimum: 0,
                          ceiling: Self.hardMaximumExpressionNestingDepth)
        try Self.validate("maximumGeneratedPlaceholderDepth", maximumGeneratedPlaceholderDepth, minimum: 0,
                          ceiling: Self.hardMaximumGeneratedPlaceholderDepth)
        try Self.validate("maximumInterpolatedOutputCharacters", maximumInterpolatedOutputCharacters, minimum: 1,
                          ceiling: Self.hardMaximumInterpolatedOutputCharacters)
        try Self.validate("maximumGeneratedExpansionCharacters", maximumGeneratedExpansionCharacters, minimum: 0,
                          ceiling: Self.hardMaximumGeneratedExpansionCharacters)

        self.maximumNumberPrecision = maximumNumberPrecision
        self.maximumAbsoluteNumberScale = maximumAbsoluteNumberScale
        self.maximumVisibleDecimalPlaces = maximumVisibleDecimalPlaces
        self.maximumCompactExponent = maximumCompactExponent
        self.maximumExpressionCharacters = maximumExpressionCharacters
        self.maximumExpressionTokens = maximumExpressionTokens
        self.maximumExpressionNestingDepth = maximumExpressionNestingDepth
        self.maximumGeneratedPlaceholderDepth = maximumGeneratedPlaceholderDepth
        self.maximumInterpolatedOutputCharacters = maximumInterpolatedOutputCharacters
        self.maximumGeneratedExpansionCharacters = maximumGeneratedExpansionCharacters
    }

    /// The first invalid setting encountered in initializer parameter order.
    public struct ValidationError: Error, Equatable, Sendable, CustomStringConvertible {
        /// The name of the first invalid initializer argument.
        public let parameter: String
        /// The rejected argument value.
        public let value: Int
        /// The inclusive range accepted for this setting.
        public let allowedRange: ClosedRange<Int>

        /// The explanation of the rejected setting.
        public var description: String {
            if value < allowedRange.lowerBound {
                let requirement = allowedRange.lowerBound == 1 ? "positive" : "non-negative"
                return "\(parameter) must be \(requirement), but was \(value)"
            }
            return "\(parameter) \(value) exceeds the hard ceiling of \(allowedRange.upperBound)"
        }
    }

    private static func validate(_ parameter: String, _ value: Int, minimum: Int, ceiling: Int) throws {
        let allowedRange = minimum...ceiling
        guard allowedRange.contains(value) else {
            throw ValidationError(parameter: parameter, value: value, allowedRange: allowedRange)
        }
    }
}
