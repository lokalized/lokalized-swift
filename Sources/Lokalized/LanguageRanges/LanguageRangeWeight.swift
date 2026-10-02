/// Java parseDouble lexical grammar for header weights. IEEE binary64 conversion
/// occurs only after this exact ASCII grammar and Java <=U+0020 trim check.
package enum LanguageRangeWeight {
    package static func parse(_ source: String) -> Double? {
        let units = Array(source.unicodeScalars)
        var start = 0, end = units.count
        while start < end && units[start].value <= 32 { start += 1 }
        while end > start && units[end - 1].value <= 32 { end -= 1 }
        let text = String(String.UnicodeScalarView(units[start..<end]))
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty else { return nil }
        var index = 0
        if bytes[index] == 43 || bytes[index] == 45 { index += 1 }
        guard index < bytes.count else { return nil }
        let special = String(decoding: bytes[index...], as: UTF8.self)
        if special == "NaN" { return .nan }
        if special == "Infinity" { return bytes.first == 45 ? -.infinity : .infinity }
        let hexadecimal = index + 1 < bytes.count && bytes[index] == 48 && (bytes[index + 1] == 120 || bytes[index + 1] == 88)
        if hexadecimal { index += 2 }
        func digit(_ byte: UInt8) -> Bool {
            (48...57).contains(byte) || (hexadecimal && ((65...70).contains(byte) || (97...102).contains(byte)))
        }
        var digits = 0
        while index < bytes.count && digit(bytes[index]) { index += 1; digits += 1 }
        if index < bytes.count && bytes[index] == 46 {
            index += 1
            while index < bytes.count && digit(bytes[index]) { index += 1; digits += 1 }
        }
        guard digits > 0 else { return nil }
        let exponent = hexadecimal ? [UInt8(112), 80] : [UInt8(101), 69]
        if index < bytes.count && exponent.contains(bytes[index]) {
            index += 1
            if index < bytes.count && (bytes[index] == 43 || bytes[index] == 45) { index += 1 }
            let firstDigit = index
            while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
            guard index > firstDigit else { return nil }
        } else if hexadecimal { return nil }
        let numericEnd = index
        if index < bytes.count && [UInt8(102), 70, 100, 68].contains(bytes[index]) { index += 1 }
        guard index == bytes.count else { return nil }
        return Double(String(decoding: bytes[..<numericEnd], as: UTF8.self))
    }
}
