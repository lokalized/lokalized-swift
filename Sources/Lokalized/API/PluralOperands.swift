/// Immutable CLDR plural operands for a displayed number.
///
/// Compact input is a displayed mantissa: 1 with exponent 6 expands to one
/// million before deriving n/i/v/w/f/t. `sourceNumber` retains the signed,
/// unexpanded value for ordinary expression comparisons and interpolation.
public struct PluralOperands: Hashable, Sendable, CustomStringConvertible {
    /// The hard ceiling for source-number precision; actual conversion uses the supplied runtime limits.
    public static let maximumNumberPrecision = TranslationRuntimeLimits.hardMaximumNumberPrecision
    /// The hard ceiling for absolute source-number scale; actual conversion uses the supplied runtime limits.
    public static let maximumAbsoluteNumberScale = TranslationRuntimeLimits.hardMaximumAbsoluteNumberScale
    /// The hard ceiling for explicit visible decimal places; actual conversion uses the supplied runtime limits.
    public static let maximumVisibleDecimalPlaces = TranslationRuntimeLimits.hardMaximumVisibleDecimalPlaces
    /// The hard ceiling for a compact exponent; actual conversion uses the supplied runtime limits.
    public static let maximumCompactExponent = TranslationRuntimeLimits.hardMaximumCompactExponent
    package static let maximumMaterializedPrecision = 12_288

    /// The absolute numeric value after compact-exponent expansion.
    public let n: ExactDecimal
    /// The integer digits of `n`.
    public let i: ExactDecimal
    /// The number of visible fractional digits in `n`, including trailing zeros.
    public let v: Int
    /// The number of visible fractional digits in `n`, excluding trailing zeros.
    public let w: Int
    /// The visible fractional digits of `n` as an integer, including trailing zeros.
    public let f: ExactDecimal
    /// The visible fractional digits of `n` as an integer, excluding trailing zeros.
    public let t: ExactDecimal
    /// The compact-decimal exponent. Equal to `e`.
    public let c: Int
    /// The compact-decimal exponent used to expand the displayed mantissa.
    public let e: Int
    /// The signed, unexpanded input used for expression comparison and interpolation.
    public let sourceNumber: ExactDecimal
    /// The explicitly requested fractional digit count, or `nil` when derived from the source representation.
    public let explicitVisibleDecimalPlaces: Int?
    /// The absolute expanded value; an alias of `n`.
    public var number: ExactDecimal { n }
    /// The compact-decimal exponent; an alias of `e`.
    public var compactExponent: Int { e }

    /// Derives exact CLDR operands from a numeric input.
    ///
    /// `visibleDecimalPlaces` sets the displayed fractional digit count without rounding. `compactExponent` expands a displayed mantissa by a power of ten and defaults to zero.
    /// Decimal inputs preserve their written scale unless explicitly overridden. Binary floats must be finite.
    /// Invalid options or numbers throw `NumericError`; removing nonzero fractional digits throws its `.roundingNecessary` category.
    public init(
        _ number: NumericValue,
        visibleDecimalPlaces: Int? = nil,
        compactExponent: Int? = nil,
        runtimeLimits: TranslationRuntimeLimits = .defaults
    ) throws {
        // Builder option precedence matches Java: exponent, visible places,
        // numeric conversion, numeric scale, then numeric precision.
        let exponent = compactExponent ?? 0
        guard exponent >= 0 else { throw NumericError(.invalidArgument, "Compact exponent must be non-negative, but was \(exponent)") }
        guard exponent <= runtimeLimits.maximumCompactExponent else {
            throw NumericError(.invalidArgument, "Compact exponent \(exponent) exceeds the maximum of \(runtimeLimits.maximumCompactExponent)")
        }
        if let visibleDecimalPlaces {
            guard visibleDecimalPlaces >= 0 else { throw NumericError(.invalidArgument, "Visible decimal places must be non-negative, but was \(visibleDecimalPlaces)") }
            guard visibleDecimalPlaces <= runtimeLimits.maximumVisibleDecimalPlaces else {
                throw NumericError(.invalidArgument, "Visible decimal places \(visibleDecimalPlaces) exceeds the maximum of \(runtimeLimits.maximumVisibleDecimalPlaces)")
            }
        }
        let resolved = try number.resolved(limits: runtimeLimits)
        let source = resolved.decimal
        var absolute = source.absoluteValue
        var effectiveScale = absolute.scale
        var materializedPrecision = absolute.precision
        if let visibleDecimalPlaces {
            effectiveScale = visibleDecimalPlaces
            materializedPrecision += max(0, effectiveScale - absolute.scale)
        } else if !resolved.explicitScale {
            effectiveScale = max(0, absolute.strippingTrailingZeros().scale)
            materializedPrecision += max(0, effectiveScale - absolute.scale)
        }
        materializedPrecision += max(0, exponent - effectiveScale)
        guard materializedPrecision <= Self.maximumMaterializedPrecision else {
            throw NumericError(.invalidArgument, "Plural operand materialized precision \(materializedPrecision) exceeds the maximum of \(Self.maximumMaterializedPrecision)")
        }
        if !resolved.explicitScale || visibleDecimalPlaces != nil { absolute = try absolute.rescaled(to: effectiveScale) }
        let expanded = absolute.movingPointRight(exponent)
        let stripped = expanded.strippingTrailingZeros()
        n = expanded
        i = expanded.integerComponent
        v = max(0, expanded.scale)
        w = max(0, stripped.scale)
        f = expanded.fractionalComponent
        t = stripped.fractionalComponent
        c = exponent
        e = exponent
        sourceNumber = source
        explicitVisibleDecimalPlaces = visibleDecimalPlaces
    }

    /// Derives exact CLDR operands from the supplied numeric input, visible fractional digits, and compact exponent.
    /// Uses the same validation and numeric error behavior as the `PluralOperands` initializer.
    public static func forNumber(
        _ number: NumericValue,
        visibleDecimalPlaces: Int? = nil,
        compactExponent: Int? = nil,
        runtimeLimits: TranslationRuntimeLimits = .defaults
    ) throws -> Self {
        try .init(number, visibleDecimalPlaces: visibleDecimalPlaces, compactExponent: compactExponent,
                  runtimeLimits: runtimeLimits)
    }
    /// Derives exact CLDR operands from the supplied numeric input, visible fractional digits, and compact exponent.
    /// Uses the same validation and numeric error behavior as the `PluralOperands` initializer.
    public static func forNumber<Value: BinaryInteger>(
        _ number: Value, visibleDecimalPlaces: Int? = nil, compactExponent: Int? = nil,
        runtimeLimits: TranslationRuntimeLimits = .defaults
    ) throws -> Self {
        try .forNumber(NumericValue(number), visibleDecimalPlaces: visibleDecimalPlaces,
                       compactExponent: compactExponent, runtimeLimits: runtimeLimits)
    }
    /// Derives exact CLDR operands from the supplied numeric input, visible fractional digits, and compact exponent.
    /// Uses the same validation and numeric error behavior as the `PluralOperands` initializer.
    public static func forNumber(
        _ number: Float, visibleDecimalPlaces: Int? = nil, compactExponent: Int? = nil,
        runtimeLimits: TranslationRuntimeLimits = .defaults
    ) throws -> Self {
        try .forNumber(.float(number), visibleDecimalPlaces: visibleDecimalPlaces,
                       compactExponent: compactExponent, runtimeLimits: runtimeLimits)
    }
    /// Derives exact CLDR operands from the supplied numeric input, visible fractional digits, and compact exponent.
    /// Uses the same validation and numeric error behavior as the `PluralOperands` initializer.
    public static func forNumber(
        _ number: Double, visibleDecimalPlaces: Int? = nil, compactExponent: Int? = nil,
        runtimeLimits: TranslationRuntimeLimits = .defaults
    ) throws -> Self {
        try .forNumber(.double(number), visibleDecimalPlaces: visibleDecimalPlaces,
                       compactExponent: compactExponent, runtimeLimits: runtimeLimits)
    }
    /// Derives exact CLDR operands from the supplied numeric input, visible fractional digits, and compact exponent.
    /// Uses the same validation and numeric error behavior as the `PluralOperands` initializer.
    public static func forNumber(
        _ number: ExactDecimal, visibleDecimalPlaces: Int? = nil, compactExponent: Int? = nil,
        runtimeLimits: TranslationRuntimeLimits = .defaults
    ) throws -> Self {
        try .forNumber(.decimal(number), visibleDecimalPlaces: visibleDecimalPlaces,
                       compactExponent: compactExponent, runtimeLimits: runtimeLimits)
    }

    /// Compares the expanded operand value and its scale, the source sign, and the compact exponent.
    public static func == (left: Self, right: Self) -> Bool {
        left.n == right.n && left.sourceNumber.signum == right.sourceNumber.signum && left.e == right.e
    }
    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(n); hasher.combine(sourceNumber.signum); hasher.combine(e)
    }
    /// A diagnostic summary of the expanded number and compact exponent.
    public var description: String { "PluralOperands{number=\(number), compactExponent=\(compactExponent)}" }
}
