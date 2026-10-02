// Copyright 2026 Lokalized. Licensed under the Apache License, Version 2.0.

/// Java 21's specified decimal selection and spelling, calculated from IEEE bits.
/// This is an original exact interval algorithm, not a translation of OpenJDK's
/// GPL-licensed Schubfach implementation. No platform formatter participates.
package enum JavaFloatingPoint {
    package static func decimalString(_ value: Float) -> String {
        let bits = value.bitPattern
        let negative = bits >> 31 != 0
        let fraction = UInt64(bits & 0x7fffff)
        let exponent = Int((bits >> 23) & 0xff)
        if exponent == 0xff {
            return fraction == 0 ? (negative ? "-Infinity" : "Infinity") : "NaN"
        }
        if exponent == 0 && fraction == 0 { return negative ? "-0.0" : "0.0" }
        let coefficient = exponent == 0 ? fraction : fraction | (1 << 23)
        let binaryExponent = exponent == 0 ? -149 : exponent - 150
        return convert(coefficient, binaryExponent, minimumExponent: -149, precision: 24,
                       maximumDigits: 9, negative: negative)
    }

    package static func decimalString(_ value: Double) -> String {
        let bits = value.bitPattern
        let negative = bits >> 63 != 0
        let fraction = bits & 0x000fffffffffffff
        let exponent = Int((bits >> 52) & 0x7ff)
        if exponent == 0x7ff {
            return fraction == 0 ? (negative ? "-Infinity" : "Infinity") : "NaN"
        }
        if exponent == 0 && fraction == 0 { return negative ? "-0.0" : "0.0" }
        let coefficient = exponent == 0 ? fraction : fraction | (1 << 52)
        let binaryExponent = exponent == 0 ? -1074 : exponent - 1075
        return convert(coefficient, binaryExponent, minimumExponent: -1074, precision: 53,
                       maximumDigits: 17, negative: negative)
    }

    package static func render(_ value: Float) -> String { decimalString(value) }
    package static func render(_ value: Double) -> String { decimalString(value) }

    private struct DecimalCandidate {
        var coefficient: UInt64
        var exponent: Int

        init(_ coefficient: UInt64, _ exponent: Int) {
            self.coefficient = coefficient
            self.exponent = exponent
            while self.coefficient % 10 == 0 {
                self.coefficient /= 10
                self.exponent += 1
            }
        }
    }

    private struct Fraction {
        let numerator: FloatingUnsigned
        let denominator: FloatingUnsigned
    }

    private struct DecimalTrial {
        let exponent: Int
        let floor: UInt64
        let left: Fraction
        let right: Fraction
    }

    /// The largest input is binary64: every exact intermediate is bounded by
    /// 2,176 bits (68 base-2^32 words). Powers are mathematical, not oracle data.
    private static let decimalPowers: [FloatingUnsigned] = {
        var values = [FloatingUnsigned(10)]
        for _ in 1..<9 { values.append(values.last!.multiplied(by: values.last!)) }
        return values
    }()

    private static func powerOfTen(_ exponent: Int) -> FloatingUnsigned {
        precondition((0...342).contains(exponent))
        var value = FloatingUnsigned(1)
        var remaining = exponent
        var index = 0
        while remaining > 0 {
            if remaining & 1 != 0 { value = value.multiplied(by: decimalPowers[index]) }
            remaining >>= 1
            index += 1
        }
        return value
    }

    /// Exact c * 2^q / 10^e. No floating-point arithmetic is used.
    private static func scaled(_ coefficient: UInt64, _ q: Int, _ e: Int) -> Fraction {
        var numerator = FloatingUnsigned(coefficient)
        var denominator = FloatingUnsigned(1)
        if q >= 0 { numerator = numerator.shifted(q) }
        else { denominator = denominator.shifted(-q) }
        if e >= 0 { denominator = denominator.multiplied(by: powerOfTen(e)) }
        else { numerator = numerator.multiplied(by: powerOfTen(-e)) }
        return Fraction(numerator: numerator, denominator: denominator)
    }

    private static func trial(_ c: UInt64, _ q: Int, _ e: Int,
                              lower: UInt64, upper: UInt64) -> DecimalTrial {
        let value = scaled(c, q, e)
        return DecimalTrial(exponent: e, floor: value.numerator.quotient(dividingBy: value.denominator),
            left: scaled(lower, q - 2, e), right: scaled(upper, q - 2, e))
    }

    private static func convert(_ c: UInt64, _ q: Int, minimumExponent: Int,
                                precision: Int, maximumDigits: Int, negative: Bool) -> String {
        // Adjacent binary values define the rounding interval. At a normal power
        // of two, the preceding spacing is half the following spacing, except
        // at the normal/subnormal boundary. A tie belongs to an even significand.
        let lower = 4 * c - ((c == 1 << (precision - 1) && q != minimumExponent) ? 1 : 2)
        let upper = 4 * c + 2
        let inclusive = c & 1 == 0
        let magnitude = 63 - c.leadingZeroBitCount + q
        let product = magnitude * 30_103
        var decade = product >= 0 ? product / 100_000 : (product - 99_999) / 100_000
        while true {
            let value = scaled(c, q, decade)
            if !(value.numerator < value.denominator) { break }
            decade -= 1
        }
        while true {
            let value = scaled(c, q, decade + 1)
            if value.numerator < value.denominator { break }
            decade += 1
        }

        // Java's minimum-length rule considers both one and two significant
        // digits when a one-digit decimal round-trips. Searching from two and
        // normalizing trailing zeros implements precisely that union.
        var trials: [DecimalTrial] = []
        for digits in 2...maximumDigits {
            var best: DecimalCandidate?
            let base = decade - digits + 1
            // Including adjoining decades handles rounding across a power of 10.
            // Increasing digit count shifts this window down one exponent.
            // Its upper two exact trials are the preceding window's lower two;
            // only the newly introduced lower exponent needs scaling/division.
            if trials.isEmpty {
                trials = ((base - 1)...(base + 1)).map { trial(c, q, $0, lower: lower, upper: upper) }
            } else {
                trials = [trial(c, q, base - 1, lower: lower, upper: upper), trials[0], trials[1]]
            }
            for trial in trials {
                let e = trial.exponent, floor = trial.floor
                let left = trial.left, right = trial.right
                for coefficient in [floor, floor + 1] where coefficient != 0 {
                    let candidate = DecimalCandidate(coefficient, e)
                    if String(candidate.coefficient).utf8.count > digits { continue }
                    let test = left.denominator.multiplied(by: FloatingUnsigned(coefficient))
                    if test < left.numerator || (!inclusive && test == left.numerator) { continue }
                    if right.numerator < test || (!inclusive && test == right.numerator) { continue }
                    if let prior = best {
                        if closer(candidate, than: prior, coefficient: c, exponent: q) { best = candidate }
                    } else { best = candidate }
                }
            }
            if let best { return (negative ? "-" : "") + format(best) }
        }
        preconditionFailure("IEEE finite values have a 9/17-digit round-tripping decimal")
    }

    private static func closer(_ candidate: DecimalCandidate, than prior: DecimalCandidate,
                               coefficient: UInt64, exponent: Int) -> Bool {
        let e = min(candidate.exponent, prior.exponent)
        let value = scaled(coefficient, exponent, e)
        let a = FloatingUnsigned(candidate.coefficient).multiplied(by: powerOfTen(candidate.exponent - e))
        let b = FloatingUnsigned(prior.coefficient).multiplied(by: powerOfTen(prior.exponent - e))
        let aDistance = value.numerator.distance(to: value.denominator.multiplied(by: a))
        let bDistance = value.numerator.distance(to: value.denominator.multiplied(by: b))
        if aDistance == bDistance {
            return candidate.coefficient & 1 == 0 && prior.coefficient & 1 != 0
        }
        return aDistance < bDistance
    }

    private static func format(_ candidate: DecimalCandidate) -> String {
        let digits = String(candidate.coefficient)
        let position = digits.utf8.count + candidate.exponent
        if position > 0 && position <= 7 {
            if candidate.exponent >= 0 {
                return digits + String(repeating: "0", count: candidate.exponent) + ".0"
            }
            let split = digits.index(digits.startIndex, offsetBy: position)
            return String(digits[..<split]) + "." + String(digits[split...])
        }
        if position <= 0 && position > -3 {
            return "0." + String(repeating: "0", count: -position) + digits
        }
        let first = digits.index(after: digits.startIndex)
        let tail = first == digits.endIndex ? "0" : String(digits[first...])
        return String(digits[..<first]) + "." + tail + "E" + String(position - 1)
    }
}

/// Small private unsigned arithmetic, used only for bounded IEEE conversion.
/// Least-significant word first; no general-purpose arbitrary-precision API.
private struct FloatingUnsigned: Comparable, Sendable {
    private var words: [UInt32]

    init(_ value: UInt64) {
        if value == 0 { words = [] }
        else if value <= UInt32.max { words = [UInt32(value)] }
        else { words = [UInt32(truncatingIfNeeded: value), UInt32(value >> 32)] }
    }

    private init(words: [UInt32]) {
        self.words = words
        while self.words.last == 0 { self.words.removeLast() }
        precondition(self.words.count <= 68)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.words.count != rhs.words.count { return lhs.words.count < rhs.words.count }
        for index in lhs.words.indices.reversed() {
            if lhs.words[index] != rhs.words[index] { return lhs.words[index] < rhs.words[index] }
        }
        return false
    }

    private var bitCount: Int {
        guard let last = words.last else { return 0 }
        return (words.count - 1) * 32 + 32 - last.leadingZeroBitCount
    }

    func shifted(_ amount: Int) -> Self {
        precondition(amount >= 0)
        if words.isEmpty || amount == 0 { return self }
        let whole = amount / 32
        let part = amount % 32
        var result = [UInt32](repeating: 0, count: words.count + whole + (part == 0 ? 0 : 1))
        for index in words.indices {
            let value = UInt64(words[index]) << part
            result[index + whole] |= UInt32(truncatingIfNeeded: value)
            if part != 0 { result[index + whole + 1] |= UInt32(value >> 32) }
        }
        return Self(words: result)
    }

    func multiplied(by other: Self) -> Self {
        if words.isEmpty || other.words.isEmpty { return Self(0) }
        var result = [UInt32](repeating: 0, count: words.count + other.words.count)
        for i in words.indices {
            var carry: UInt64 = 0
            for j in other.words.indices {
                // Product + existing word + carry fits exactly in UInt64.
                let value = UInt64(words[i]) * UInt64(other.words[j]) + UInt64(result[i + j]) + carry
                result[i + j] = UInt32(truncatingIfNeeded: value)
                carry = value >> 32
            }
            result[i + other.words.count] = UInt32(carry)
        }
        return Self(words: result)
    }

    private func subtracting(_ other: Self) -> Self {
        precondition(!(self < other))
        var result = words
        var borrow: UInt64 = 0
        for index in result.indices {
            let subtrahend = (index < other.words.count ? UInt64(other.words[index]) : 0) + borrow
            let value = UInt64(result[index])
            result[index] = UInt32(truncatingIfNeeded: value &- subtrahend)
            borrow = value < subtrahend ? 1 : 0
        }
        precondition(borrow == 0)
        return Self(words: result)
    }

    func distance(to other: Self) -> Self {
        self < other ? other.subtracting(self) : subtracting(other)
    }

    /// The caller scales into at most 18 decimal digits, so quotient fits UInt64.
    func quotient(dividingBy denominator: Self) -> UInt64 {
        precondition(!denominator.words.isEmpty)
        if self < denominator { return 0 }
        let shift = bitCount - denominator.bitCount
        precondition(shift < 64)
        var remainder = self
        var result: UInt64 = 0
        for bit in stride(from: shift, through: 0, by: -1) {
            let divisor = denominator.shifted(bit)
            if !(remainder < divisor) {
                remainder = remainder.subtracting(divisor)
                result |= UInt64(1) << bit
            }
        }
        return result
    }
}
