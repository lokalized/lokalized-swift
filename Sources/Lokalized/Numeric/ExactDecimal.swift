/// An exact signed decimal coefficient and scale, independent of Foundation's
/// decimal precision. Written trailing zeroes are part of its representation.
///
/// Equality and hashing preserve scale, matching Java BigDecimal. Use
/// `compare(to:)` for numerical comparison: 1 and 1.00 compare equally while
/// remaining different values in a set or dictionary.
public struct ExactDecimal: Hashable, Sendable, CustomStringConvertible {
    /// Decimal digits without leading zeroes; zero is represented by one digit.
    package let digits: [UInt8]
    package let negative: Bool
    public let scale: Int

    public var precision: Int { digits.count }
    public var signum: Int { isZero ? 0 : (negative ? -1 : 1) }
    public var coefficient: String {
        (negative ? "-" : "") + String(decoding: digits, as: UTF8.self)
    }
    public var isZero: Bool { digits.count == 1 && digits[0] == 48 }
    public var isIntegerValued: Bool { scale <= 0 || isZero || trailingZeroCount >= scale }

    /// Parses ASCII decimal text, including an optional sign, decimal point,
    /// and exponent. Whitespace and implicit rounding are never accepted.
    public init(_ text: String, runtimeLimits: TranslationRuntimeLimits = .defaults) throws {
        self = try Self.parse(text, integerOnly: false, description: "Number", limits: runtimeLimits)
    }

    /// For bounded, already validated derived coefficients. Derived plural
    /// operands may have more digits than their source number's precision cap.
    package init(digits: [UInt8], negative: Bool = false, scale: Int = 0) {
        let first = digits.firstIndex { $0 != 48 }
        self.digits = first.map { Array(digits[$0...]) } ?? [48]
        self.negative = first != nil && negative
        self.scale = scale
    }

    package static func integer(_ value: Int) -> Self {
        // Int.min cannot be negated, so parsing its decimal spelling is safer.
        let text = String(value)
        let bytes = Array(text.utf8)
        return .init(digits: bytes.first == 45 ? Array(bytes.dropFirst()) : bytes,
                     negative: value < 0)
    }

    package static func parse(_ text: String, integerOnly: Bool, description: String,
                              limits: TranslationRuntimeLimits) throws -> Self {
        var iterator = text.utf8.makeIterator()
        var current = iterator.next()
        var negative = false
        if current == 45 || current == 43 {
            negative = current == 45
            current = iterator.next()
        }
        var digits: [UInt8] = []
        var significantCount = 0
        var totalDigits = 0
        var fractionalDigits = 0
        var significant = false
        func consumeDigit(_ byte: UInt8, fractional: Bool) {
            totalDigits += 1
            if fractional { fractionalDigits += 1 }
            if byte != 48 { significant = true }
            if significant {
                significantCount += 1
                // Refusal diagnostics still count all significant digits, but
                // malformed/unbounded input cannot allocate an unbounded buffer.
                if digits.count < TranslationRuntimeLimits.hardMaximumNumberPrecision { digits.append(byte) }
            }
        }
        while let byte = current, (48...57).contains(byte) {
            consumeDigit(byte, fractional: false)
            current = iterator.next()
        }
        if !integerOnly && current == 46 {
            current = iterator.next()
            while let byte = current, (48...57).contains(byte) {
                consumeDigit(byte, fractional: true)
                current = iterator.next()
            }
        }
        guard totalDigits > 0 else { throw invalidText(text, integerOnly: integerOnly) }
        var exponent: Int64 = 0
        if !integerOnly && (current == 69 || current == 101) {
            current = iterator.next()
            var exponentNegative = false
            if current == 45 || current == 43 {
                exponentNegative = current == 45
                current = iterator.next()
            }
            var exponentDigits = 0
            var nonzeroDigits = 0
            var exponentOverflow = false
            while let byte = current, (48...57).contains(byte) {
                exponentDigits += 1
                if byte != 48 || nonzeroDigits > 0 { nonzeroDigits += 1 }
                if nonzeroDigits <= 10 { exponent = exponent * 10 + Int64(byte - 48) }
                else { exponentOverflow = true }
                current = iterator.next()
            }
            guard exponentDigits > 0 && current == nil else { throw invalidText(text, integerOnly: integerOnly) }
            if exponentOverflow { throw NumericError(.invalidDecimal, "Too many nonzero exponent digits.") }
            if exponentNegative { exponent = -exponent }
            guard exponent >= Int64(Int32.min) && exponent <= Int64(Int32.max) else {
                throw NumericError(.invalidDecimal, "Exponent overflow.")
            }
        }
        guard current == nil else { throw invalidText(text, integerOnly: integerOnly) }
        let scale = Int64(fractionalDigits) - exponent
        guard scale >= Int64(Int32.min) && scale <= Int64(Int32.max) else {
            throw NumericError(.invalidDecimal, "Exponent overflow.")
        }
        guard abs(scale) <= Int64(limits.maximumAbsoluteNumberScale) else {
            throw NumericError(.invalidArgument, "\(description) scale \(scale) exceeds the maximum absolute scale of \(limits.maximumAbsoluteNumberScale)")
        }
        let precision = max(1, significantCount)
        guard precision <= limits.maximumNumberPrecision else {
            throw NumericError(.invalidArgument, "\(description) precision \(precision) exceeds the maximum of \(limits.maximumNumberPrecision)")
        }
        return .init(digits: digits, negative: negative, scale: Int(scale))
    }

    private static func invalidText(_ text: String, integerOnly: Bool) -> NumericError {
        .init(.invalidDecimal, "Invalid \(integerOnly ? "integer" : "decimal") text '\(text)'")
    }

    package func validate(description: String = "Number", limits: TranslationRuntimeLimits) throws {
        guard abs(scale) <= limits.maximumAbsoluteNumberScale else {
            throw NumericError(.invalidArgument, "\(description) scale \(scale) exceeds the maximum absolute scale of \(limits.maximumAbsoluteNumberScale)")
        }
        guard precision <= limits.maximumNumberPrecision else {
            throw NumericError(.invalidArgument, "\(description) precision \(precision) exceeds the maximum of \(limits.maximumNumberPrecision)")
        }
    }

    /// Java BigDecimal.toPlainString: no exponent, with observable trailing zeroes.
    public var plainString: String {
        let body: String
        if scale <= 0 {
            body = String(decoding: digits, as: UTF8.self) + (isZero ? "" : String(repeating: "0", count: -scale))
        } else if scale >= digits.count {
            body = "0." + String(repeating: "0", count: scale - digits.count) + String(decoding: digits, as: UTF8.self)
        } else {
            let at = digits.count - scale
            body = String(decoding: digits[..<at], as: UTF8.self) + "." + String(decoding: digits[at...], as: UTF8.self)
        }
        return (negative ? "-" : "") + body
    }

    /// Java BigDecimal.toString: plain notation when scale is nonnegative and
    /// adjusted exponent is at least -6; otherwise canonical scientific notation.
    public var description: String {
        let exponent = precision - 1 - scale
        if scale >= 0 && exponent >= -6 { return plainString }
        let mantissa = String(decoding: digits.prefix(1), as: UTF8.self)
            + (digits.count > 1 ? "." + String(decoding: digits.dropFirst(), as: UTF8.self) : "")
        return (negative ? "-" : "") + mantissa + "E" + (exponent >= 0 ? "+" : "") + String(exponent)
    }

    /// Numerical comparison, ignoring representational scale; returns -1, 0, or 1.
    public func compare(to other: Self) -> Int {
        if signum != other.signum { return signum < other.signum ? -1 : 1 }
        if isZero { return 0 }
        let leftPlaces = digits.count - scale
        let rightPlaces = other.digits.count - other.scale
        var comparison = 0
        if leftPlaces != rightPlaces { comparison = leftPlaces < rightPlaces ? -1 : 1 }
        else {
            for index in 0..<max(digits.count, other.digits.count) {
                let left = index < digits.count ? digits[index] : 48
                let right = index < other.digits.count ? other.digits[index] : 48
                if left != right { comparison = left < right ? -1 : 1; break }
            }
        }
        return negative ? -comparison : comparison
    }

    /// Exact remainder for a positive small integral divisor. Division truncates
    /// toward zero, so the remainder follows the dividend's sign. Nonnegative
    /// scale is retained; a negative scale is expanded to an integer first.
    public func remainder(dividingBy divisor: Int) throws -> Self {
        guard divisor > 0 && divisor <= Int.max / 10 else {
            throw NumericError(.invalidArgument, "Modulus must be positive and no greater than \(Int.max / 10), but was \(divisor)")
        }
        var remainder = 0
        let integerDigits = scale > 0 ? max(0, digits.count - scale) : digits.count
        for digit in digits.prefix(integerDigits) { remainder = (remainder * 10 + Int(digit - 48)) % divisor }
        if scale < 0 {
            for _ in 0..<(-scale) { remainder = (remainder * 10) % divisor }
            return .integer(negative ? -remainder : remainder)
        }
        if scale == 0 { return .integer(negative ? -remainder : remainder) }
        var coefficient = Array(String(remainder).utf8)
        if scale > digits.count { coefficient.append(contentsOf: repeatElement(UInt8(48), count: scale - digits.count)) }
        coefficient.append(contentsOf: digits.suffix(min(scale, digits.count)))
        return .init(digits: coefficient, negative: negative, scale: scale)
    }

    package var trailingZeroCount: Int {
        var count = 0
        for digit in digits.reversed() { if digit != 48 { break }; count += 1 }
        return count
    }
    package var absoluteValue: Self { .init(digits: digits, scale: scale) }
    package func strippingTrailingZeros() -> Self {
        if isZero { return .integer(0) }
        let count = trailingZeroCount
        return .init(digits: Array(digits.dropLast(count)), negative: negative, scale: scale - count)
    }
    package func rescaled(to newScale: Int) throws -> Self {
        let difference = newScale - scale
        if difference == 0 { return self }
        if isZero { return .init(digits: [48], scale: newScale) }
        if difference > 0 {
            return .init(digits: digits + repeatElement(UInt8(48), count: difference), negative: negative, scale: newScale)
        }
        guard trailingZeroCount >= -difference else { throw NumericError(.roundingNecessary, "Rounding necessary") }
        return .init(digits: Array(digits.dropLast(-difference)), negative: negative, scale: newScale)
    }
    package func movingPointRight(_ places: Int) -> Self {
        let shiftedScale = scale - places
        if shiftedScale >= 0 { return .init(digits: digits, negative: negative, scale: shiftedScale) }
        if isZero { return .integer(0) }
        return .init(digits: digits + repeatElement(UInt8(48), count: -shiftedScale), negative: negative)
    }
    package var integerComponent: Self {
        if scale <= 0 { return movingPointRight(0) }
        if scale >= digits.count { return .integer(0) }
        return .init(digits: Array(digits.dropLast(scale)), negative: negative)
    }
    package var fractionalComponent: Self {
        if scale <= 0 { return .integer(0) }
        return .init(digits: Array(digits.suffix(min(scale, digits.count))))
    }
}
