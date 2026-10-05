import Foundation

/// Ordered members retain duplicates until the catalog decoder can diagnose them.
package struct JSONMember: Sendable {
    package let name: ExactString
    package let value: JSONValue
    package let location: JSONSourceLocation

    package init(name: ExactString, value: JSONValue, location: JSONSourceLocation) {
        self.name = name
        self.value = value
        self.location = location
    }
}

/// Numbers retain their source spelling; no binary floating-point conversion occurs.
package indirect enum JSONValue: Sendable {
    case object([JSONMember])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}

package struct JSONSourceLocation: Equatable, Sendable {
    /// Zero-based UTF-16 offset after the optional leading BOM.
    package let offset: Int
    /// One-based line and UTF-16 column; CRLF is a single line break.
    package let line: Int
    package let column: Int

    package init(offset: Int, line: Int, column: Int) {
        self.offset = offset
        self.line = line
        self.column = column
    }
}

package struct JSONReadError: Error, CustomStringConvertible, Sendable {
    package let reason: String
    package let location: JSONSourceLocation
    package var description: String {
        "\(reason) at line \(location.line), column \(location.column) (UTF-16 offset \(location.offset))"
    }
}

package struct JSONReadingLimits: Sendable {
    package let maximumCharacters: Int
    package let maximumDepth: Int
    package let maximumNodes: Int

    package init(maximumCharacters: Int = 8_388_608, maximumDepth: Int = 64, maximumNodes: Int = 100_000) {
        precondition(maximumCharacters > 0 && maximumCharacters <= Int.max / 4)
        // Development corpus envelopes contain intentionally over-limit catalog
        // fixtures. Public catalog limits remain capped separately at 128.
        precondition((1...256).contains(maximumDepth) && maximumNodes > 0)
        self.maximumCharacters = maximumCharacters
        self.maximumDepth = maximumDepth
        self.maximumNodes = maximumNodes
    }
}

/// A strict UTF-8/JSON reader used by both the library and development harness.
/// It scans UTF-16 code units rather than grapheme clusters. Duplicate members,
/// canonical-equivalent strings, and decimal literals survive parsing unchanged.
package struct JSONReader {
    private let units: [UInt16]
    private let limits: JSONReadingLimits
    private var cursor = 0
    private var line = 1
    private var column = 1
    private var previousWasCR = false
    private var nodes = 0

    package static func parse(_ data: Data, limits: JSONReadingLimits = .init()) throws -> JSONValue {
        // Bound the raw allocation before decoding; one UTF-16 unit needs at most
        // four UTF-8 bytes. File-loading budgets will impose a separate byte cap.
        guard data.count <= limits.maximumCharacters * 4 + 3 else {
            throw JSONReadError(reason: "JSON input exceeds character budget", location: .init(offset: 0, line: 1, column: 1))
        }
        // Safe only after validation. Unlike String(data:encoding:), this keeps
        // the BOM so exactly one is removed by the shared String entry point.
        return try parse(decodeUTF8(data), limits: limits)
    }

    package static func parse(_ source: String, limits: JSONReadingLimits = .init(), allowLeadingBOM: Bool = true) throws -> JSONValue {
        let hasBOM = allowLeadingBOM && source.unicodeScalars.first?.value == 0xFEFF
        let count = source.utf16.count - (hasBOM ? 1 : 0)
        guard count <= limits.maximumCharacters else {
            throw JSONReadError(reason: "JSON input exceeds character budget", location: .init(offset: 0, line: 1, column: 1))
        }
        var units = Array(source.utf16)
        if hasBOM { units.removeFirst() }
        var reader = JSONReader(units: units, limits: limits)
        let value = try reader.readValue(depth: 0)
        reader.skipWhitespace()
        guard reader.cursor == units.count else { throw reader.error("Unexpected content after JSON value") }
        return value
    }

    package static func decodeUTF8(_ data: Data) throws -> String {
        let bytes = Array(data)
        try validateUTF8(bytes)
        return String(decoding: bytes, as: UTF8.self)
    }

    package static func validateUTF8(_ bytes: [UInt8]) throws {
        var index = 0
        while index < bytes.count {
            let first = bytes[index]
            let length: Int
            let secondRange: ClosedRange<UInt8>
            switch first {
            case 0x00...0x7F: index += 1; continue
            case 0xC2...0xDF: length = 2; secondRange = 0x80...0xBF
            case 0xE0: length = 3; secondRange = 0xA0...0xBF
            case 0xE1...0xEC, 0xEE...0xEF: length = 3; secondRange = 0x80...0xBF
            case 0xED: length = 3; secondRange = 0x80...0x9F
            case 0xF0: length = 4; secondRange = 0x90...0xBF
            case 0xF1...0xF3: length = 4; secondRange = 0x80...0xBF
            case 0xF4: length = 4; secondRange = 0x80...0x8F
            default: throw utf8Error(bytes, at: index)
            }
            guard index + length <= bytes.count, secondRange.contains(bytes[index + 1]) else {
                throw utf8Error(bytes, at: index)
            }
            for offset in 2..<length where !(0x80...0xBF).contains(bytes[index + offset]) {
                throw utf8Error(bytes, at: index)
            }
            index += length
        }
    }

    private static func utf8Error(_ bytes: [UInt8], at index: Int) -> JSONReadError {
        let prefix = String(decoding: bytes[..<index], as: UTF8.self)
        let units = Array(prefix.utf16.dropFirst(prefix.unicodeScalars.first?.value == 0xFEFF ? 1 : 0))
        var line = 1
        var column = 1
        var previousWasCR = false
        for unit in units {
            if unit == 13 { line += 1; column = 1 }
            else if unit == 10 { if !previousWasCR { line += 1 }; column = 1 }
            else { column += 1 }
            previousWasCR = unit == 13
        }
        return .init(reason: "Invalid UTF-8 at byte \(index)", location: .init(offset: units.count, line: line, column: column))
    }

    private var location: JSONSourceLocation { .init(offset: cursor, line: line, column: column) }
    private func error(_ reason: String) -> JSONReadError { .init(reason: reason, location: location) }
    private var peek: UInt16? { cursor < units.count ? units[cursor] : nil }

    @discardableResult
    private mutating func take() -> UInt16 {
        let unit = units[cursor]
        cursor += 1
        if unit == 13 { line += 1; column = 1 }
        else if unit == 10 { if !previousWasCR { line += 1 }; column = 1 }
        else { column += 1 }
        previousWasCR = unit == 13
        return unit
    }

    private mutating func skipWhitespace() {
        while let unit = peek, unit == 32 || unit == 9 || unit == 10 || unit == 13 { take() }
    }

    private mutating func readValue(depth: Int) throws -> JSONValue {
        skipWhitespace()
        guard nodes < limits.maximumNodes else { throw error("JSON node budget exceeded") }
        nodes += 1
        guard let unit = peek else { throw error("Expected JSON value") }
        switch unit {
        case 123, 91:
            guard depth < limits.maximumDepth else { throw error("JSON nesting depth exceeded") }
            return unit == 123 ? try readObject(depth: depth + 1) : try readArray(depth: depth + 1)
        case 34: return .string(try readString())
        case 116: try readLiteral([116, 114, 117, 101]); return .bool(true)
        case 102: try readLiteral([102, 97, 108, 115, 101]); return .bool(false)
        case 110: try readLiteral([110, 117, 108, 108]); return .null
        case 45, 48...57: return .number(try readNumber())
        default: throw error("Expected JSON value")
        }
    }

    private mutating func readObject(depth: Int) throws -> JSONValue {
        take()
        skipWhitespace()
        var members: [JSONMember] = []
        if peek == 125 { take(); return .object(members) }
        while true {
            skipWhitespace()
            let nameLocation = location
            guard peek == 34 else { throw error("Expected object member name") }
            let name = ExactString(try readString())
            skipWhitespace()
            guard peek == 58 else { throw error("Expected ':' after member name") }
            take()
            members.append(.init(name: name, value: try readValue(depth: depth), location: nameLocation))
            skipWhitespace()
            if peek == 125 { take(); return .object(members) }
            guard peek == 44 else { throw error("Expected ',' or '}'") }
            take()
        }
    }

    private mutating func readArray(depth: Int) throws -> JSONValue {
        take()
        skipWhitespace()
        var values: [JSONValue] = []
        if peek == 93 { take(); return .array(values) }
        while true {
            values.append(try readValue(depth: depth))
            skipWhitespace()
            if peek == 93 { take(); return .array(values) }
            guard peek == 44 else { throw error("Expected ',' or ']'") }
            take()
        }
    }

    private mutating func readLiteral(_ literal: [UInt16]) throws {
        for unit in literal {
            guard peek == unit else { throw error("Invalid JSON literal") }
            take()
        }
    }

    private mutating func readNumber() throws -> String {
        let start = cursor
        if peek == 45 { take() }
        if peek == 48 { take() }
        else {
            guard let unit = peek, (49...57).contains(unit) else { throw error("Expected digit") }
            repeat { take() } while peek.map { (48...57).contains($0) } == true
        }
        if peek == 46 {
            take()
            guard peek.map({ (48...57).contains($0) }) == true else { throw error("Expected fractional digit") }
            repeat { take() } while peek.map { (48...57).contains($0) } == true
        }
        if peek == 101 || peek == 69 {
            take()
            if peek == 43 || peek == 45 { take() }
            guard peek.map({ (48...57).contains($0) }) == true else { throw error("Expected exponent digit") }
            repeat { take() } while peek.map { (48...57).contains($0) } == true
        }
        return String(decoding: units[start..<cursor], as: UTF16.self)
    }

    private mutating func readString() throws -> String {
        take() // opening quote, checked by caller
        var output: [UInt16] = []
        var pendingHighSurrogate: JSONSourceLocation?
        while let unit = peek {
            if unit == 34 {
                if let pendingHighSurrogate {
                    throw JSONReadError(reason: "Unpaired high surrogate", location: pendingHighSurrogate)
                }
                take(); return String(decoding: output, as: UTF16.self)
            }
            guard unit >= 32 else { throw error("Unescaped control character in string") }
            let characterLocation = location
            let character: UInt16
            if unit != 92 { character = take() }
            else {
                take()
                guard let escaped = peek else { throw error("Unterminated string escape") }
                switch escaped {
                case 34, 92, 47: character = take()
                case 98: take(); character = 8
                case 102: take(); character = 12
                case 110: take(); character = 10
                case 114: take(); character = 13
                case 116: take(); character = 9
                case 117: take(); character = try readHexUnit()
                default: throw error("Invalid string escape")
                }
            }
            // Decode the following character before judging a pending high
            // surrogate. Malformed escapes, raw controls and EOF take priority,
            // matching the reference parser's observable first-error position.
            if let pending = pendingHighSurrogate {
                guard (0xDC00...0xDFFF).contains(character) else {
                    throw JSONReadError(reason: "Unpaired high surrogate", location: pending)
                }
                pendingHighSurrogate = nil
            } else if (0xD800...0xDBFF).contains(character) {
                pendingHighSurrogate = characterLocation
            } else if (0xDC00...0xDFFF).contains(character) {
                throw JSONReadError(reason: "Unpaired low surrogate", location: characterLocation)
            }
            output.append(character)
        }
        throw error("Unterminated string")
    }

    private mutating func readHexUnit() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let unit = peek else { throw error("Incomplete Unicode escape") }
            let digit: UInt16
            switch unit {
            case 48...57: digit = unit - 48
            case 65...70: digit = unit - 55
            case 97...102: digit = unit - 87
            default: throw error("Invalid Unicode escape")
            }
            take()
            value = value * 16 + digit
        }
        return value
    }
}
