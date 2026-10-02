/// Original RFC 3492 Bootstring codec. All arithmetic that consumes input is
/// checked against the pinned URL oracle's signed 31-bit arithmetic ceiling;
/// decoding never constructs a surrogate or an out-of-range scalar.
package enum PunycodeCodec {
    private static let base: UInt64 = 36
    private static let maximumArithmetic: UInt64 = 0x7FFFFFFF
    private static func threshold(_ k: UInt64, _ bias: UInt64) -> UInt64 {
        if k <= bias { return 1 }
        if k >= bias + 26 { return 26 }
        return k - bias
    }
    private static func adapt(_ delta: UInt64, count: UInt64, first: Bool) -> UInt64 {
        var delta = first ? delta / 700 : delta / 2
        delta += delta / count
        var k: UInt64 = 0
        while delta > 455 { delta /= 35; k += 36 }
        return k + 36 * delta / (delta + 38)
    }
    private static func digit(_ byte: UInt8) -> UInt64? {
        switch byte {
        case 97...122: return UInt64(byte - 97)
        case 65...90: return UInt64(byte - 65)
        case 48...57: return UInt64(byte - 22)
        default: return nil
        }
    }
    private static func byte(_ digit: UInt64) -> UInt8 {
        digit < 26 ? UInt8(digit + 97) : UInt8(digit + 22)
    }
    package static func encode(_ input: [UInt32]) -> String? {
        guard input.allSatisfy({ $0 <= 0x10FFFF && !(0xD800...0xDFFF).contains($0) }) else { return nil }
        var output = input.filter { $0 < 128 }.map(UInt8.init)
        let basic = output.count
        if basic > 0 { output.append(45) }
        var handled = basic, n: UInt64 = 128, delta: UInt64 = 0, bias: UInt64 = 72
        while handled < input.count {
            guard let minimum = input.lazy.map(UInt64.init).filter({ $0 >= n }).min() else { return nil }
            let (step, stepOverflow) = (minimum - n).multipliedReportingOverflow(by: UInt64(handled) + 1)
            let (advanced, overflow) = delta.addingReportingOverflow(step)
            guard !stepOverflow, !overflow, advanced <= maximumArithmetic else { return nil }
            delta = advanced; n = minimum
            for scalar in input {
                let c = UInt64(scalar)
                if c < n {
                    let (value, overflow) = delta.addingReportingOverflow(1)
                    guard !overflow, value <= maximumArithmetic else { return nil }; delta = value
                }
                if c == n {
                    var q = delta, k = base
                    while true {
                        let t = threshold(k, bias)
                        if q < t { break }
                        output.append(byte(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t); k += base
                    }
                    output.append(byte(q))
                    bias = adapt(delta, count: UInt64(handled) + 1, first: handled == basic)
                    delta = 0; handled += 1
                }
            }
            let (next, incrementOverflow) = delta.addingReportingOverflow(1)
            guard !incrementOverflow, next <= maximumArithmetic else { return nil }; delta = next; n += 1
        }
        return String(decoding: output, as: UTF8.self)
    }
    package static func decode(_ input: [UInt8]) -> [UInt32]? {
        guard input.allSatisfy({ $0 < 128 }) else { return nil }
        var output: [UInt32] = [], position = 0
        if let delimiter = input.lastIndex(of: 45) {
            output = input[..<delimiter].map(UInt32.init); position = delimiter + 1
        }
        var n: UInt64 = 128, index: UInt64 = 0, bias: UInt64 = 72
        while position < input.count {
            let previous = index
            var weight: UInt64 = 1, k = base
            while true {
                guard position < input.count, let digit = digit(input[position]) else { return nil }
                position += 1
                let (product, productOverflow) = digit.multipliedReportingOverflow(by: weight)
                let (advanced, overflow) = index.addingReportingOverflow(product)
                guard !productOverflow, !overflow, advanced <= maximumArithmetic else { return nil }; index = advanced
                let t = threshold(k, bias)
                if digit < t { break }
                let (nextWeight, weightOverflow) = weight.multipliedReportingOverflow(by: base - t)
                guard !weightOverflow, nextWeight <= maximumArithmetic else { return nil }; weight = nextWeight; k += base
            }
            let count = UInt64(output.count) + 1
            bias = adapt(index - previous, count: count, first: previous == 0)
            let (scalar, overflow) = n.addingReportingOverflow(index / count)
            guard !overflow, scalar <= 0x10FFFF, !(0xD800...0xDFFF).contains(scalar) else { return nil }
            n = scalar; index %= count
            output.insert(UInt32(n), at: Int(index)); index += 1
        }
        return output
    }
}
