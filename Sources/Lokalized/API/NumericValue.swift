/// Closed numeric inputs with explicit Java-compatible conversion semantics.
/// Decimal values retain their written scale. Native integers and binary
/// floating-point values use normalized canonical decimals. Big integers retain
/// scale zero. Float and Double remain distinct widths throughout conversion.
public enum NumericValue: Hashable, Sendable, CustomStringConvertible {
    /// A signed 64-bit integer input.
    case integer(Int64)
    /// An unsigned 64-bit integer input.
    case unsignedInteger(UInt64)
    /// An arbitrary-precision integer represented by signed ASCII decimal text. Use `forBigInteger` to validate it immediately.
    case bigInteger(String)
    /// An exact decimal input whose written scale is preserved.
    case decimal(ExactDecimal)
    /// A 32-bit binary floating-point input. Plural conversion rejects NaN and infinity.
    case float(Float)
    /// A 64-bit binary floating-point input. Plural conversion rejects NaN and infinity.
    case double(Double)

    /// Wraps a numeric input while preserving its numeric kind. Integer inputs use a signed, unsigned, or arbitrary-precision representation as needed. Conversion limits apply when the value is evaluated.
    public init<Value: BinaryInteger>(_ value: Value) {
        if let signed = Int64(exactly: value) { self = .integer(signed) }
        else if let unsigned = UInt64(exactly: value) { self = .unsignedInteger(unsigned) }
        else { self = .bigInteger(String(value)) }
    }
    /// Wraps a numeric input while preserving its numeric kind. Integer inputs use a signed, unsigned, or arbitrary-precision representation as needed. Conversion limits apply when the value is evaluated.
    public init(_ value: Float) { self = .float(value) }
    /// Wraps a numeric input while preserving its numeric kind. Integer inputs use a signed, unsigned, or arbitrary-precision representation as needed. Conversion limits apply when the value is evaluated.
    public init(_ value: Double) { self = .double(value) }
    /// Wraps a numeric input while preserving its numeric kind. Integer inputs use a signed, unsigned, or arbitrary-precision representation as needed. Conversion limits apply when the value is evaluated.
    public init(_ value: ExactDecimal) { self = .decimal(value) }

    /// Parses exact ASCII decimal text while preserving its written scale. Throws `NumericError` for malformed text or exceeded numeric limits.
    public static func forDecimal(_ text: String, runtimeLimits: TranslationRuntimeLimits = .defaults) throws -> Self {
        .decimal(try ExactDecimal(text, runtimeLimits: runtimeLimits))
    }
    /// Parses signed ASCII integer text with no decimal point or exponent. Throws `NumericError` for malformed text or exceeded numeric limits.
    public static func forBigInteger(_ text: String, runtimeLimits: TranslationRuntimeLimits = .defaults) throws -> Self {
        let decimal = try ExactDecimal.parse(text, integerOnly: true, description: "Number", limits: runtimeLimits)
        return .bigInteger(decimal.coefficient)
    }
    /// Wraps a 32-bit floating-point value. Non-finite inputs are rejected when evaluated as plural operands.
    public static func forFloat(_ value: Float) -> Self { .float(value) }
    /// Wraps a 64-bit floating-point value. Non-finite inputs are rejected when evaluated as plural operands.
    public static func forDouble(_ value: Double) -> Self { .double(value) }

    /// Rendering follows the source representation rather than the absolute,
    /// compact-expanded plural operand. Binary floats use pinned Java spelling.
    public var description: String {
        switch self {
        case .integer(let value): String(value)
        case .unsignedInteger(let value): String(value)
        case .bigInteger(let text):
            (try? ExactDecimal.parse(text, integerOnly: true, description: "Number", limits: .numericHardCeilings))?.coefficient ?? text
        case .decimal(let decimal): decimal.description
        case .float(let value): JavaFloatingPoint.render(value)
        case .double(let value): JavaFloatingPoint.render(value)
        }
    }

    package func resolved(limits: TranslationRuntimeLimits) throws -> (decimal: ExactDecimal, explicitScale: Bool) {
        let value: ExactDecimal
        let explicit: Bool
        switch self {
        case .integer(let integer):
            // JDK boxed integral types normalize BEFORE applying numeric limits.
            value = try ExactDecimal.parse(String(integer), integerOnly: true, description: "Number",
                                          limits: .numericHardCeilings).strippingTrailingZeros()
            explicit = false
        case .unsignedInteger(let integer):
            value = try ExactDecimal.parse(String(integer), integerOnly: true, description: "Number",
                                          limits: .numericHardCeilings).strippingTrailingZeros()
            explicit = false
        case .bigInteger(let text):
            value = try ExactDecimal.parse(text, integerOnly: true, description: "Number", limits: limits)
            explicit = false
        case .decimal(let decimal): value = decimal; explicit = true
        case .float(let number):
            guard number.isFinite else { throw NumericError(.invalidArgument, "Number must be finite, but was \(JavaFloatingPoint.render(number))") }
            value = try ExactDecimal.parse(JavaFloatingPoint.decimalString(number), integerOnly: false,
                                          description: "Number", limits: .numericHardCeilings).strippingTrailingZeros()
            explicit = false
        case .double(let number):
            guard number.isFinite else { throw NumericError(.invalidArgument, "Number must be finite, but was \(JavaFloatingPoint.render(number))") }
            value = try ExactDecimal.parse(JavaFloatingPoint.decimalString(number), integerOnly: false,
                                          description: "Number", limits: .numericHardCeilings).strippingTrailingZeros()
            explicit = false
        }
        try value.validate(limits: limits)
        return (value, explicit)
    }

    /// Compares numeric kind and source representation. Decimal scale and floating-point bit patterns remain significant.
    public static func == (left: Self, right: Self) -> Bool {
        switch (left, right) {
        case (.integer(let a), .integer(let b)): a == b
        case (.unsignedInteger(let a), .unsignedInteger(let b)): a == b
        case (.bigInteger(let a), .bigInteger(let b)): ExactString(a) == ExactString(b)
        case (.decimal(let a), .decimal(let b)): a == b
        case (.float(let a), .float(let b)): a.bitPattern == b.bitPattern
        case (.double(let a), .double(let b)): a.bitPattern == b.bitPattern
        default: false
        }
    }
    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .integer(let value): hasher.combine(0); hasher.combine(value)
        case .unsignedInteger(let value): hasher.combine(1); hasher.combine(value)
        case .bigInteger(let value): hasher.combine(2); hasher.combine(ExactString(value))
        case .decimal(let value): hasher.combine(3); hasher.combine(value)
        case .float(let value): hasher.combine(4); hasher.combine(value.bitPattern)
        case .double(let value): hasher.combine(5); hasher.combine(value.bitPattern)
        }
    }
}

package extension TranslationRuntimeLimits {
    static let numericHardCeilings: Self = {
        do {
            return try Self(maximumNumberPrecision: hardMaximumNumberPrecision,
                            maximumAbsoluteNumberScale: hardMaximumAbsoluteNumberScale,
                            maximumVisibleDecimalPlaces: hardMaximumVisibleDecimalPlaces,
                            maximumCompactExponent: hardMaximumCompactExponent)
        } catch { preconditionFailure("Library numeric hard ceilings are invalid: \(error)") }
    }()
}
