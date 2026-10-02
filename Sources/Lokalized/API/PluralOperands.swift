/// Immutable CLDR plural operands for a displayed number.
///
/// Compact input is a displayed mantissa: 1 with exponent 6 expands to one
/// million before deriving n/i/v/w/f/t. `sourceNumber` retains the signed,
/// unexpanded value for ordinary expression comparisons and interpolation.
public struct PluralOperands: Hashable, Sendable, CustomStringConvertible {
    public static let maximumNumberPrecision = TranslationRuntimeLimits.hardMaximumNumberPrecision
    public static let maximumAbsoluteNumberScale = TranslationRuntimeLimits.hardMaximumAbsoluteNumberScale
    public static let maximumVisibleDecimalPlaces = TranslationRuntimeLimits.hardMaximumVisibleDecimalPlaces
    public static let maximumCompactExponent = TranslationRuntimeLimits.hardMaximumCompactExponent
    package static let maximumMaterializedPrecision = 12_288

    public let n: ExactDecimal
    public let i: ExactDecimal
    public let v: Int
    public let w: Int
    public let f: ExactDecimal
    public let t: ExactDecimal
    public let c: Int
    public let e: Int
    public let sourceNumber: ExactDecimal
    public let explicitVisibleDecimalPlaces: Int?
    public var number: ExactDecimal { n }
    public var compactExponent: Int { e }

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

    public static func forNumber(
        _ number: NumericValue,
        visibleDecimalPlaces: Int? = nil,
        compactExponent: Int? = nil,
        runtimeLimits: TranslationRuntimeLimits = .defaults
    ) throws -> Self {
        try .init(number, visibleDecimalPlaces: visibleDecimalPlaces, compactExponent: compactExponent,
                  runtimeLimits: runtimeLimits)
    }
    public static func forNumber<Value: BinaryInteger>(
        _ number: Value, visibleDecimalPlaces: Int? = nil, compactExponent: Int? = nil,
        runtimeLimits: TranslationRuntimeLimits = .defaults
    ) throws -> Self {
        try .forNumber(NumericValue(number), visibleDecimalPlaces: visibleDecimalPlaces,
                       compactExponent: compactExponent, runtimeLimits: runtimeLimits)
    }
    public static func forNumber(
        _ number: Float, visibleDecimalPlaces: Int? = nil, compactExponent: Int? = nil,
        runtimeLimits: TranslationRuntimeLimits = .defaults
    ) throws -> Self {
        try .forNumber(.float(number), visibleDecimalPlaces: visibleDecimalPlaces,
                       compactExponent: compactExponent, runtimeLimits: runtimeLimits)
    }
    public static func forNumber(
        _ number: Double, visibleDecimalPlaces: Int? = nil, compactExponent: Int? = nil,
        runtimeLimits: TranslationRuntimeLimits = .defaults
    ) throws -> Self {
        try .forNumber(.double(number), visibleDecimalPlaces: visibleDecimalPlaces,
                       compactExponent: compactExponent, runtimeLimits: runtimeLimits)
    }
    public static func forNumber(
        _ number: ExactDecimal, visibleDecimalPlaces: Int? = nil, compactExponent: Int? = nil,
        runtimeLimits: TranslationRuntimeLimits = .defaults
    ) throws -> Self {
        try .forNumber(.decimal(number), visibleDecimalPlaces: visibleDecimalPlaces,
                       compactExponent: compactExponent, runtimeLimits: runtimeLimits)
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.n == right.n && left.sourceNumber.signum == right.sourceNumber.signum && left.e == right.e
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(n); hasher.combine(sourceNumber.signum); hasher.combine(e)
    }
    public var description: String { "PluralOperands{number=\(number), compactExponent=\(compactExponent)}" }
}
